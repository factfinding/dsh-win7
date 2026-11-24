# Builds Windows 7 variants of the Python wheels in the win-x64 primary runtime whose native code imports
# Windows 8+ functions. deepseek-harness's scripts/primary-runtime/prepare.ts takes the wheels that lock.json marks
# with "win7Shim" from DSH_WIN7_PYTHON_WHEELS (this script's -Out); lock.json records the SHA-256 of these files.
#
#   cryptography (used by pdfminer.six, pdfplumber and pypdf): its Rust extension
#     cryptography/hazmat/bindings/_rust.pyd imports WaitOnAddress, WakeByAddressSingle, WakeByAddressAll
#     (api-ms-win-core-synch-l1-2-0.dll) and ProcessPrng (bcryptprimitives.dll). Both DLL names are renamed to
#     dshw7.dll, the shim libvips uses, which goes beside the extension.
#   onnxruntime (PyMuPDF's layout analysis, which find_tables and to_markdown use): onnxruntime_pybind11_state.pyd
#     and onnxruntime.dll import CreateFile2, GetSystemTimePreciseAsFileTime, GetProcessMitigationPolicy (kernel32),
#     CreateDXGIFactory2 (dxgi) and PathCchRemoveBackslash/PathCchRemoveFileSpec (api-ms-win-core-path-l1-1-0).
#     Their kernel32, dxgi and api-ms-win-core-path-l1-1-0 imports are renamed to dsho.dll: shim\dsho.c, built with
#     forwarders generated from both files' imports (so it differs from the voice-input dsho.dll in the overlay).
#   pymupdf: not a missing import but a missing feature. MuPDF creates output files with fopen mode "wb+x", and the
#     Universal CRT of Windows 7 (KB2999226, 10.0.10240) ends the process on the unknown 'x' (0xC0000417), so
#     Document.save(path) crashed. mupdfcpp64.dll's api-ms-win-crt-stdio-l1-1-0.dll import is renamed to dshmu.dll
#     (shim\dshmu.c: fopen/_wfopen create the file exclusively themselves; the other stdio functions forward to ucrtbase).
#     The static import check cannot see this one; it was found by running PyMuPDF on Windows 7.
#
# Python 3.8+ loads extension modules with LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR, so the loader finds a DLL beside the
# .pyd (on Windows 7 that flag needs KB2533623, a documented prerequisite).
# The original wheels come from PyPI and must match the hashes below. A rebuilt wheel keeps the original entries,
# their order and timestamps; RECORD gets the new hashes and sizes and lists the added DLL. The shims are built
# with /Brepro, so rerunning the script reproduces the same wheel bytes.
# Usage: scripts\build-win7-python-wheels.ps1 [-Out out\win7-python-wheels]
param(
  [string] $Out = (Join-Path (Split-Path $PSScriptRoot) 'out\win7-python-wheels')
)
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$pypi = Join-Path $Out 'pypi'
$build = Join-Path $Out 'build'
if (Test-Path $build) { Remove-Item -LiteralPath $build -Recurse -Force }
New-Item -ItemType Directory -Force $pypi, $build | Out-Null
Add-Type -AssemblyName System.IO.Compression
$dumpbin = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC' -Recurse -Filter dumpbin.exe |
  Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1 -ExpandProperty FullName

function Sha256([string] $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

# RECORD hash: urlsafe Base64 of the SHA-256 digest without padding (PEP 376/427).
function RecordHash([string] $path) {
  $digest = [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($path))
  'sha256=' + [Convert]::ToBase64String($digest).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-Original([string] $url, [string] $sha256) {
  $path = Join-Path $pypi ([Uri] $url).Segments[-1]
  if (-not (Test-Path -LiteralPath $path)) {
    Invoke-WebRequest -Uri $url -OutFile "$path.part" -MaximumRetryCount 5 -RetryIntervalSec 3
    Move-Item -LiteralPath "$path.part" $path
  }
  if ((Sha256 $path) -ne $sha256) { Remove-Item -LiteralPath $path; throw "checksum mismatch: $url" }
  $path
}

function Expand-Entries([string] $wheel, [string[]] $names, [string] $destination) {
  $zip = [IO.Compression.ZipFile]::OpenRead($wheel)
  try {
    foreach ($name in $names) {
      $entry = $zip.GetEntry($name)
      if ($null -eq $entry) { throw "$wheel has no $name" }
      $file = Join-Path $destination $name
      New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
      $stream = $entry.Open()
      try { $target = [IO.File]::Create($file); try { $stream.CopyTo($target) } finally { $target.Dispose() } } finally { $stream.Dispose() }
    }
  } finally { $zip.Dispose() }
}

function Imports([string] $file) {
  $tsv = "$file.imports.tsv"
  & "$scripts\dump-imports.ps1" -Exe $file -OutTsv $tsv | Out-Null
  Get-Content $tsv | ForEach-Object { $section, $dll, $name = $_.Split("`t"); [pscustomobject]@{ section = $section; dll = $dll.ToLower(); name = $name } }
}

function Exports([string] $dll) {
  $table = $false
  foreach ($line in & $dumpbin /nologo /exports $dll) {
    if ($line -match '^\s+ordinal\s+hint') { $table = $true; continue }
    if ($table -and $line -match '^\s+Summary') { break }
    if ($table -and $line -match '^\s+\d+\s+[0-9A-F]+\s+(?:[0-9A-F]{8}\s+)?(\S+)') { $Matches[1] }
  }
}

# Every import the patched file takes from the shim must be a shim export, and no renamed DLL may remain.
function Assert-Patched([string] $file, [string] $shim, [string[]] $renamed) {
  $imports = Imports $file
  $left = $imports | Where-Object { $_.dll -in $renamed }
  if ($left) { throw "$file still imports $(($left | ForEach-Object { "$($_.dll)!$($_.name)" }) -join ', ')" }
  $exports = Exports $shim
  $absent = $imports | Where-Object { $_.dll -eq (Split-Path $shim -Leaf).ToLower() -and $_.name -notin $exports }
  if ($absent) { throw "$(Split-Path $shim -Leaf) lacks $(($absent.name) -join ', ') for $file" }
  "  {0}: {1} imports from {2}" -f (Split-Path $file -Leaf), @($imports | Where-Object { $_.dll -eq (Split-Path $shim -Leaf).ToLower() }).Count, (Split-Path $shim -Leaf)
}

# Rewrites $source into $target: $replace maps entry names to new contents; each $add item inserts the entry
# { name, file } right after the entry named { after }, with that entry's timestamp.
function Write-Wheel([string] $source, [string] $target, [hashtable] $replace, [object[]] $add) {
  $archive = [IO.Compression.ZipFile]::OpenRead($source)
  try {
    $record = @($archive.Entries | Where-Object { $_.FullName -match '^[^/]+\.dist-info/RECORD$' })
    if ($record.Count -ne 1) { throw "$source has $($record.Count) RECORD files" }
    $reader = [IO.StreamReader]::new($record[0].Open())
    try { $lines = $reader.ReadToEnd().Split("`n") | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ } } finally { $reader.Dispose() }
    if ($lines -match '"') { throw "$source RECORD has quoted paths" }
    $rows = [Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($line in $lines) {
      $path = $line.Substring(0, $line.IndexOf(','))
      if ($replace.ContainsKey($path)) {
        $rows.Add("$path,$(RecordHash $replace[$path]),$((Get-Item -LiteralPath $replace[$path]).Length)")
        $seen[$path] = $true
      } else { $rows.Add($line) }
    }
    $unknown = $replace.Keys | Where-Object { -not $seen.ContainsKey($_) }
    if ($unknown) { throw "$source RECORD lacks $($unknown -join ', ')" }
    foreach ($item in $add) {
      if ($rows | Where-Object { $_.StartsWith("$($item.name),") }) { throw "$source already has $($item.name)" }
      $rows.Add("$($item.name),$(RecordHash $item.file),$((Get-Item -LiteralPath $item.file).Length)")
    }
    $recordBytes = [Text.UTF8Encoding]::new($false).GetBytes(($rows -join "`n") + "`n")

    $stream = [IO.File]::Create($target)
    $output = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    try {
      function Copy-Entry($name, $time, $attributes, [byte[]] $bytes) {
        $entry = $output.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $time
        $entry.ExternalAttributes = $attributes
        $writer = $entry.Open()
        try { $writer.Write($bytes, 0, $bytes.Length) } finally { $writer.Dispose() }
      }
      foreach ($entry in $archive.Entries) {
        # Assigned in each branch: a byte array written to the pipeline would be unrolled (and an empty one lost).
        if ($entry.FullName -eq $record[0].FullName) { $bytes = $recordBytes }
        elseif ($replace.ContainsKey($entry.FullName)) { $bytes = [IO.File]::ReadAllBytes($replace[$entry.FullName]) }
        else {
          $memory = [IO.MemoryStream]::new()
          $reader = $entry.Open()
          try { $reader.CopyTo($memory) } finally { $reader.Dispose() }
          $bytes = $memory.ToArray()
        }
        Copy-Entry $entry.FullName $entry.LastWriteTime $entry.ExternalAttributes $bytes
        foreach ($item in $add | Where-Object { $_.after -eq $entry.FullName }) {
          Copy-Entry $item.name $entry.LastWriteTime $entry.ExternalAttributes ([IO.File]::ReadAllBytes($item.file))
        }
      }
      $orphans = $add | Where-Object { -not $archive.GetEntry($_.after) }
      if ($orphans) { throw "$source has no $($orphans.after -join ', ')" }
    } finally { $output.Dispose(); $stream.Dispose() }
  } finally { $archive.Dispose() }
  $hash = Sha256 $target
  Set-Content -LiteralPath "$target.sha256" -Value $hash -NoNewline -Encoding ascii
  "{0}  {1}" -f $hash, (Split-Path $target -Leaf)
}

# cryptography + dshw7.dll
$cryptography = Get-Original 'https://files.pythonhosted.org/packages/9a/4f/adfc442765721292fff86d314ce385d3249d22db42295c0dd057727b60f3/cryptography-50.0.2-cp311-abi3-win_amd64.whl' '7afa5a6602a9f29af1f3a2965f831bae7c9d5d597b7cbb716d41ab3b7d89879c'
$rust = 'cryptography/hazmat/bindings/_rust.pyd'
$work = Join-Path $build 'cryptography'
Expand-Entries $cryptography @($rust) "$work\original"
cmd /c "`"$scripts\build-shim.cmd`" dshw7 `"`" `"$work`"" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dshw7 build failed' }
$rustPatched = Join-Path $work '_rust.pyd'
$synch = @{ 'api-ms-win-core-synch-l1-2-0.dll' = 'dshw7.dll'; 'bcryptprimitives.dll' = 'dshw7.dll' }
& "$scripts\patch-imports.ps1" -File "$work\original\$rust" -Out $rustPatched -Rename $synch | Out-Host
Assert-Patched $rustPatched (Join-Path $work 'dshw7.dll') @($synch.Keys)
Write-Wheel $cryptography (Join-Path $Out (Split-Path $cryptography -Leaf)) @{ $rust = $rustPatched } @(
  @{ name = 'cryptography/hazmat/bindings/dshw7.dll'; file = (Join-Path $work 'dshw7.dll'); after = $rust })

# onnxruntime + dsho.dll
$onnxruntime = Get-Original 'https://files.pythonhosted.org/packages/a9/3e/27039badc39a1b01628b6b40b1ff1bf4a886e6dfb2f311c483606b7c86f7/onnxruntime-1.32.0-cp312-cp312-win_amd64.whl' 'efe7456952c243a05a53d5b8732953625144642c2f3989094277f6217f0c0c40'
$ortFiles = 'onnxruntime/capi/onnxruntime_pybind11_state.pyd', 'onnxruntime/capi/onnxruntime.dll'
$work = Join-Path $build 'onnxruntime'
Expand-Entries $onnxruntime $ortFiles "$work\original"
$merged = Join-Path $work 'imports.tsv'
foreach ($file in $ortFiles) {
  & "$scripts\dump-imports.ps1" -Exe "$work\original\$file" -OutTsv "$work\$(Split-Path $file -Leaf).tsv" | Out-Null
  Get-Content "$work\$(Split-Path $file -Leaf).tsv" | Add-Content $merged
}
$ortDlls = 'kernel32.dll', 'dxgi.dll', 'api-ms-win-core-path-l1-1-0.dll'
& "$scripts\gen-forward-def.ps1" -Tsv $merged -Library dsho -Dlls $ortDlls -Implemented @{
  CreateFile2 = 'DshCreateFile2'
  GetSystemTimePreciseAsFileTime = 'DshGetSystemTimePreciseAsFileTime'
  GetProcessMitigationPolicy = 'DshGetProcessMitigationPolicy'
  CreateDXGIFactory2 = 'DshCreateDXGIFactory2'
  PathCchRemoveBackslash = 'DshPathCchRemoveBackslash'
  PathCchRemoveFileSpec = 'DshPathCchRemoveFileSpec'
} -Out (Join-Path $work 'dsho.def') | Out-Host
cmd /c "`"$scripts\build-shim.cmd`" dsho `"$work\dsho.def`" `"$work`"" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dsho build failed' }
$ortRename = @{}
foreach ($dll in $ortDlls) { $ortRename[$dll] = 'dsho.dll' }
$replace = @{}
foreach ($file in $ortFiles) {
  $patched = Join-Path $work (Split-Path $file -Leaf)
  & "$scripts\patch-imports.ps1" -File "$work\original\$file" -Out $patched -Rename $ortRename | Out-Host
  Assert-Patched $patched (Join-Path $work 'dsho.dll') $ortDlls
  $replace[$file] = $patched
}
Write-Wheel $onnxruntime (Join-Path $Out (Split-Path $onnxruntime -Leaf)) $replace @(
  @{ name = 'onnxruntime/capi/dsho.dll'; file = (Join-Path $work 'dsho.dll'); after = 'onnxruntime/capi/onnxruntime.dll' })

# pymupdf + dshmu.dll
$pymupdf = Get-Original 'https://files.pythonhosted.org/packages/9d/1a/397ef60ed67c5b99c8584d2f07c3970b0cd693283212a233b06737f7c859/pymupdf-2.1-cp311-abi3-win_amd64.whl' 'e1122bbc3a1212396f0d70d19f78e084991b59ebdfc9d846c28ca8b509de01ad'
$mupdf = 'pymupdf/mupdfcpp64.dll'
$work = Join-Path $build 'pymupdf'
Expand-Entries $pymupdf @($mupdf) "$work\original"
$stdio = 'api-ms-win-crt-stdio-l1-1-0.dll'
& "$scripts\dump-imports.ps1" -Exe "$work\original\$mupdf" -OutTsv "$work\imports.tsv" | Out-Null
& "$scripts\gen-forward-def.ps1" -Tsv "$work\imports.tsv" -Library dshmu -Dlls $stdio -ForwardTo @{ $stdio = 'ucrtbase' } -Implemented @{
  _wfopen = 'DshWfopen'
  fopen = 'DshFopen'
} -Out (Join-Path $work 'dshmu.def') | Out-Host
cmd /c "`"$scripts\build-shim.cmd`" dshmu `"$work\dshmu.def`" `"$work`"" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dshmu build failed' }
$mupdfPatched = Join-Path $work 'mupdfcpp64.dll'
& "$scripts\patch-imports.ps1" -File "$work\original\$mupdf" -Out $mupdfPatched -Rename @{ $stdio = 'dshmu.dll' } | Out-Host
Assert-Patched $mupdfPatched (Join-Path $work 'dshmu.dll') @($stdio)
Write-Wheel $pymupdf (Join-Path $Out (Split-Path $pymupdf -Leaf)) @{ $mupdf = $mupdfPatched } @(
  @{ name = 'pymupdf/dshmu.dll'; file = (Join-Path $work 'dshmu.dll'); after = $mupdf })
