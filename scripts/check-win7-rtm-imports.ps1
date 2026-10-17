# Checks every PE file under -Root against Windows 7 SP1 x64 plus the documented prerequisites: KB2533623
# (SetDefaultDllDirectories, AddDllDirectory, RemoveDllDirectory), KB4474419 (-Updates; it brings, among others,
# advapi32 6.1.7601.24384 with EventSetInformation, which node.exe imports) and the VC++ 2015-2022 runtime with UCRT.
# An -Updates directory holds System32\ and SysWOW64\ copies of the DLLs that update installs (taken from a
# machine that has it, at the update's own file versions); they replace the SP1 originals.
# System DLL exports come from the SP1 install.wim (-Wim, image 4: System32 for x64 files, SysWOW64 for x86 files),
# extracted on demand into -RtmDir.
# Only load-time (static) imports are reported: a missing one stops the program before it can print anything.
# DLLs the loader finds next to the importing file, in the top directory of -Root (the application directory) or in a
# *.libs directory (Python wheels add theirs with os.add_dll_directory) count as shipped; UCRT/VC runtime DLLs and
# Python's own DLLs are not checked. A DLL shipped elsewhere is reported like a missing system DLL.
# Usage: check-win7-rtm-imports.ps1 -Root <dir> [-Wim out\win7-sp1-rtm\install.wim] [-RtmDir out\win7-sp1-rtm\sys32]
param(
  [Parameter(Mandatory)] [string] $Root,
  [string] $Wim = (Join-Path (Split-Path $PSScriptRoot) 'out\win7-sp1-rtm\install.wim'),
  [string] $RtmDir = (Join-Path (Split-Path $PSScriptRoot) 'out\win7-sp1-rtm\sys32'),
  [string[]] $Updates = @(Join-Path (Split-Path $PSScriptRoot) 'out\win7-sp1-rtm\updates\KB4474419')
)
$ErrorActionPreference = 'Stop'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$dumpbin = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC' -Recurse -Filter dumpbin.exe |
  Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1 -ExpandProperty FullName
New-Item -ItemType Directory -Force $RtmDir | Out-Null

$exports = @{}
$absent = @{}
function Get-Exports([string] $dll, [string] $system) {
  $key = "$system\$dll"
  if ($exports.ContainsKey($key) -or $absent.ContainsKey($key)) { return $exports[$key] }
  $directory = if ($system -eq 'System32') { $RtmDir } else { "$RtmDir-$system" }
  New-Item -ItemType Directory -Force $directory | Out-Null
  $file = Join-Path $directory $dll
  foreach ($update in $Updates) {
    $updated = Join-Path (Join-Path $update $system) $dll
    if (Test-Path -LiteralPath $updated) { $file = $updated }
  }
  if (-not (Test-Path -LiteralPath $file)) { & $sevenZip e -y "-o$directory" $Wim "4\Windows\$system\$dll" 2>&1 | Out-Null }
  if (-not (Test-Path -LiteralPath $file)) {
    # Side-by-side system DLLs such as GdiPlus.dll live only in WinSxS; the loader still resolves them by name.
    $arch = if ($system -eq 'System32') { 'amd64' } else { 'x86' }
    & $sevenZip e -y -r "-o$directory" $Wim "4\Windows\winsxs\$($arch)_microsoft.windows.*\$dll" 2>&1 | Out-Null
  }
  if (-not (Test-Path -LiteralPath $file)) { $absent[$key] = $true; return $null }
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  $table = $false
  foreach ($line in & $dumpbin /nologo /exports $file) {
    if ($line -match '^\s+ordinal\s+hint') { $table = $true; continue }
    if ($table -and $line -match '^\s+Summary') { break }
    if ($table -and $line -match '^\s+\d+\s+[0-9A-F]+\s+(?:[0-9A-F]{8}\s+)?(\S+)') { [void]$set.Add($Matches[1]) }
  }
  if ($dll -eq 'kernel32.dll') { 'SetDefaultDllDirectories', 'AddDllDirectory', 'RemoveDllDirectory' | ForEach-Object { [void]$set.Add($_) } }
  $exports[$key] = $set
  return $set
}

$skip = '^(api-ms-win-crt-.*|ucrtbase|vcruntime140(_1)?|msvcp140(_\w+)?|concrt140|vcomp140|python3\d*|python\d+)\.dll$'
$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Include *.exe, *.dll, *.node, *.pyd |
  Where-Object { $head = [IO.File]::ReadAllBytes($_.FullName)[0..1]; $head[0] -eq 0x4D -and $head[1] -eq 0x5A }
$shipped = New-Object 'System.Collections.Generic.HashSet[string]'
Get-ChildItem -LiteralPath $Root -File -Filter *.dll | ForEach-Object { [void]$shipped.Add($_.Name.ToLower()) }
Get-ChildItem -LiteralPath $Root -Recurse -Directory -Filter *.libs | Get-ChildItem -File -Filter *.dll | ForEach-Object { [void]$shipped.Add($_.Name.ToLower()) }
$problems = 0
foreach ($file in $files) {
  # IMAGE_FILE_HEADER.Machine: 0x014C is x86, checked against SysWOW64.
  $bytes = [IO.File]::ReadAllBytes($file.FullName)
  $system = if ([BitConverter]::ToUInt16($bytes, [BitConverter]::ToInt32($bytes, 0x3C) + 4) -eq 0x014C) { 'SysWOW64' } else { 'System32' }
  $dll = $null
  $section = 'static'
  foreach ($line in & $dumpbin /nologo /imports $file.FullName) {
    if ($line -match '^\s+Summary\s*$') { break }
    if ($line -match 'Section contains the following delay load imports') { $section = 'delay' }
    if ($section -ne 'static') { continue }
    if ($line -match '^\s{4}(\S+\.(dll|drv|exe|cpl))\s*$') {
      $dll = $Matches[1].ToLower()
      $provided = $dll -match $skip -or $shipped.Contains($dll) -or (Test-Path -LiteralPath (Join-Path $file.DirectoryName $dll))
      continue
    }
    if ($null -eq $dll -or $provided) { continue }
    if ($line -match '^\s+[0-9A-F]+\s+(\S+)\s*$') {
      $function = $Matches[1]
      $set = Get-Exports $dll $system
      $relative = $file.FullName.Substring($Root.TrimEnd('\').Length + 1)
      if ($null -eq $set) { "MISSING DLL   $relative -> $dll!$function"; $problems++ }
      elseif (-not $set.Contains($function)) { "MISSING FUNC  $relative -> $dll!$function"; $problems++ }
    }
  }
}
$baseline = (@('Windows 7 SP1', 'KB2533623') + ($Updates | ForEach-Object { Split-Path $_ -Leaf }) + 'VC++/UCRT') -join ' + '
"checked $($files.Count) PE files; $problems missing static imports on $baseline"
