# Builds the Windows 7 runtime overlay that deepseek-harness's prepare-dsh.ts applies when
# DSH_WIN7_RUNTIME_OVERLAY points at it (apps/desktop/scripts/runtime-overlay.ts).
#
# Originals come from -Reference, a node_modules tree with the same dependency versions the
# packaged runtime installs (default: out\host-web\node_modules, an npm install of
# @deepseek-ai/dsh@0.2.0-rc.2). Each replacement records the original's SHA-256, so packaging
# fails loudly if it installs a different version.
#
# Entries (paths relative to the packaged runtime root):
#   @vscode/ripgrep-win32-x64/bin/rg.exe              <- out\rg-15.0.0-win7-x64.exe (scripts\build-ripgrep.ps1)
#   @img/sharp-win32-x64/lib/libvips-42.dll           <- imports renamed to dshw7.dll; + dshw7.dll
#   @deepseek-ai/libreoffice-kit-win32-x64/bin/...exe <- kernel32/user32/bcrypt imports renamed to dshlo.dll; + dshlo.dll
#   @deepseek-ai/libreoffice-kit/lib/{index,cli}.js   <- read-only-aware rm (shim\libreoffice-kit-rm.js)
#   sherpa-onnx-win-x64/onnxruntime.dll               <- kernel32/dxgi/api-ms-win-core-path imports renamed to dsho.dll; + dsho.dll
#   @dsh-win7/pty-winpty/                             <- out\pty-winpty (scripts\build-pty-winpty.ps1)
#
# The manifest's "pins" records the -Reference versions of ripgrep, sharp, LibreOffice Kit and sherpa-onnx (and
# their win32-x64 packages); prepare-dsh.ts adds them to the runtime project's pnpm overrides, so packaging
# installs exactly the versions these files were made from and tested with.
param(
  [string] $Reference = (Join-Path (Split-Path $PSScriptRoot) 'out\host-web\node_modules'),
  [string] $Out = (Join-Path (Split-Path $PSScriptRoot) 'out\win7-runtime-overlay')
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$scripts = $PSScriptRoot
$files = Join-Path $Out 'files'
if (Test-Path $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
New-Item -ItemType Directory -Force $files | Out-Null
$entries = [System.Collections.Generic.List[object]]::new()

function Sha256([string] $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }
function Reference([string] $relative) {
  $path = Join-Path $Reference $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "reference file missing: $path" }
  $path
}
function Add-Entry([string] $path, [string] $source, [string] $replaces) {
  $entry = [ordered]@{ path = "node_modules/$path"; source = $source.Replace('\', '/') }
  if ($replaces) { $entry.replaces = $replaces }
  $entries.Add($entry)
}
function Stage([string] $from, [string] $name) {
  $target = Join-Path $files $name
  New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
  Copy-Item -LiteralPath $from $target -Recurse -Force
  "files/$($name.Replace('\', '/'))"
}

# ripgrep
$rg = Reference '@vscode\ripgrep-win32-x64\bin\rg.exe'
Add-Entry '@vscode/ripgrep-win32-x64/bin/rg.exe' (Stage (Join-Path $root 'out\rg-15.0.0-win7-x64.exe') 'ripgrep\rg.exe') (Sha256 $rg)

# sharp: libvips-42.dll + dshw7.dll
cmd /c "`"$scripts\build-shim.cmd`" dshw7" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dshw7 build failed' }
$vips = Reference '@img\sharp-win32-x64\lib\libvips-42.dll'
New-Item -ItemType Directory -Force (Join-Path $files 'sharp') | Out-Null
& "$scripts\patch-imports.ps1" -File $vips -Out (Join-Path $files 'sharp\libvips-42.dll') -Rename @{ 'api-ms-win-core-synch-l1-2-0.dll' = 'dshw7.dll'; 'bcryptprimitives.dll' = 'dshw7.dll' } | Out-Host
Add-Entry '@img/sharp-win32-x64/lib/libvips-42.dll' 'files/sharp/libvips-42.dll' (Sha256 $vips)
Add-Entry '@img/sharp-win32-x64/lib/dshw7.dll' (Stage (Join-Path $root 'out\shim\dshw7.dll') 'sharp\dshw7.dll') $null

# LibreOffice Kit engine: libreoffice-kit.exe + dshlo.dll (forwarders generated from this exe's imports)
$kitExe = Reference '@deepseek-ai\libreoffice-kit-win32-x64\bin\libreoffice-kit.exe'
$kitImports = Join-Path $Out 'libreoffice-kit-imports.tsv'
& "$scripts\dump-imports.ps1" -Exe $kitExe -OutTsv $kitImports | Out-Host
& "$scripts\gen-forward-def.ps1" -Tsv $kitImports -Library dshlo -Dlls kernel32.dll, user32.dll, bcrypt.dll -Implemented @{
  GetCurrentPackageFullName = 'DshGetCurrentPackageFullName'
  GetSystemTimePreciseAsFileTime = 'DshGetSystemTimePreciseAsFileTime'
  SetThreadDpiAwarenessContext = 'DshSetThreadDpiAwarenessContext'
  BCryptKeyDerivation = 'DshBCryptKeyDerivation'
} -Out (Join-Path $root 'out\shim\dshlo.def') | Out-Host
cmd /c "`"$scripts\build-shim.cmd`" dshlo `"$root\out\shim\dshlo.def`"" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dshlo build failed' }
New-Item -ItemType Directory -Force (Join-Path $files 'libreoffice-kit') | Out-Null
& "$scripts\patch-imports.ps1" -File $kitExe -Out (Join-Path $files 'libreoffice-kit\libreoffice-kit.exe') -Rename @{ 'kernel32.dll' = 'dshlo.dll'; 'user32.dll' = 'dshlo.dll'; 'bcrypt.dll' = 'dshlo.dll' } | Out-Host
Add-Entry '@deepseek-ai/libreoffice-kit-win32-x64/bin/libreoffice-kit.exe' 'files/libreoffice-kit/libreoffice-kit.exe' (Sha256 $kitExe)
Add-Entry '@deepseek-ai/libreoffice-kit-win32-x64/bin/dshlo.dll' (Stage (Join-Path $root 'out\shim\dshlo.dll') 'libreoffice-kit\dshlo.dll') $null

# LibreOffice Kit JavaScript: rm that clears read-only attributes on Windows
$anchor = 'import { copyFile, lstat, mkdir, mkdtemp, open, readFile, rm, stat, symlink, unlink, writeFile } from "node:fs/promises";'
$replacement = $anchor.Replace(' rm,', ' rm as fsRm,') + "`n" + ([IO.File]::ReadAllText((Join-Path $root 'shim\libreoffice-kit-rm.js')) -replace "`r`n", "`n").TrimEnd()
New-Item -ItemType Directory -Force (Join-Path $files 'libreoffice-kit-lib') | Out-Null
foreach ($name in 'index.js', 'cli.js') {
  $original = Reference "@deepseek-ai\libreoffice-kit\lib\$name"
  $text = [IO.File]::ReadAllText($original)
  if (([regex]::Matches($text, [regex]::Escape($anchor))).Count -ne 1) { throw "fs/promises import anchor not found exactly once in $original" }
  [IO.File]::WriteAllText((Join-Path $files "libreoffice-kit-lib\$name"), $text.Replace($anchor, $replacement), [Text.UTF8Encoding]::new($false))
  Add-Entry "@deepseek-ai/libreoffice-kit/lib/$name" "files/libreoffice-kit-lib/$name" (Sha256 $original)
}

# Voice input: ONNX Runtime (sherpa-onnx-win-x64) + dsho.dll (forwarders generated from this DLL's imports)
$ort = Reference 'sherpa-onnx-win-x64\onnxruntime.dll'
$ortImports = Join-Path $Out 'onnxruntime-imports.tsv'
& "$scripts\dump-imports.ps1" -Exe $ort -OutTsv $ortImports | Out-Host
& "$scripts\gen-forward-def.ps1" -Tsv $ortImports -Library dsho -Dlls kernel32.dll, dxgi.dll, api-ms-win-core-path-l1-1-0.dll -Implemented @{
  CreateFile2 = 'DshCreateFile2'
  GetSystemTimePreciseAsFileTime = 'DshGetSystemTimePreciseAsFileTime'
  GetProcessMitigationPolicy = 'DshGetProcessMitigationPolicy'
  CreateDXGIFactory2 = 'DshCreateDXGIFactory2'
  PathCchRemoveBackslash = 'DshPathCchRemoveBackslash'
  PathCchRemoveFileSpec = 'DshPathCchRemoveFileSpec'
} -Out (Join-Path $root 'out\shim\dsho.def') | Out-Host
cmd /c "`"$scripts\build-shim.cmd`" dsho `"$root\out\shim\dsho.def`"" | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'dsho build failed' }
New-Item -ItemType Directory -Force (Join-Path $files 'sherpa-onnx') | Out-Null
& "$scripts\patch-imports.ps1" -File $ort -Out (Join-Path $files 'sherpa-onnx\onnxruntime.dll') -Rename @{ 'kernel32.dll' = 'dsho.dll'; 'dxgi.dll' = 'dsho.dll'; 'api-ms-win-core-path-l1-1-0.dll' = 'dsho.dll' } | Out-Host
Add-Entry 'sherpa-onnx-win-x64/onnxruntime.dll' 'files/sherpa-onnx/onnxruntime.dll' (Sha256 $ort)
Add-Entry 'sherpa-onnx-win-x64/dsho.dll' (Stage (Join-Path $root 'out\shim\dsho.dll') 'sherpa-onnx\dsho.dll') $null

# winpty terminal backend
& "$scripts\build-pty-winpty.ps1" | Out-Null
Add-Entry '@dsh-win7/pty-winpty' (Stage (Join-Path $root 'out\pty-winpty') 'pty-winpty') $null

$pins = [ordered]@{}
foreach ($name in '@vscode/ripgrep', '@vscode/ripgrep-win32-x64', 'sharp', '@img/sharp-win32-x64', '@deepseek-ai/libreoffice-kit', '@deepseek-ai/libreoffice-kit-win32-x64', 'sherpa-onnx-node', 'sherpa-onnx-win-x64') {
  $pins[$name] = ([IO.File]::ReadAllText((Reference "$($name.Replace('/', '\'))\package.json")) | ConvertFrom-Json).version
}

$manifest = [ordered]@{ schemaVersion = 1; pins = $pins; entries = $entries }
[IO.File]::WriteAllText((Join-Path $Out 'manifest.json'), ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
"overlay: $Out ($($entries.Count) entries)"
$pins.GetEnumerator() | ForEach-Object { "  pin {0}@{1}" -f $_.Key, $_.Value }
$entries | ForEach-Object { "  {0}{1}" -f $_.path, $(if ($_.replaces) { "  (replaces $($_.replaces.Substring(0, 12)))" } else { '  (new)' }) }
