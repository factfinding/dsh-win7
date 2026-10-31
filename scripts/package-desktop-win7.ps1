# Packages the DeepSeek Harness desktop app for Windows 7 x64 (unsigned) from deepseek-harness\.
# Inputs, all built in this directory (see docs/porting.md):
#   out\node-v24.21.0-win-x64.zip            Win7 node.exe for the primary runtime (scripts\build-node.cmd)
#   out\win7-runtime-overlay\                rg, libvips, LibreOffice Kit, winpty + version pins (scripts\build-win7-overlay.ps1)
#   out\pwsh\PowerShell-7.2.24-win-x64.zip   PowerShell 7.2 for the Host PATH on Win7, with its .sha256
#   out\electron-v44.2.0-win32-x64.zip       Win7-patched Electron (scripts\electron-build.cmd)
# Needs deepseek-harness\apps\desktop\.env.windows. Extra arguments go to the package script, e.g. --check, or
# --build-version 0.2.1-rc.5.20261031.1 for a test build that outranks the release it extends.
# The update feed is the dsh-win7 Releases' latest/download/ directory unless DSH_WIN7_UPDATE_URL names another
# (for example a local server while testing updates); the build then carries app-update.yml and emits nightly.yml.
# Output: deepseek-harness\apps\desktop\.desktop-build\targets\win-x64\unsigned-artifacts\
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$out = Join-Path $root 'out'
$inputs = @{
  DSH_PRIMARY_RUNTIME_NODE_ARCHIVE = Join-Path $out 'node-v24.21.0-win-x64.zip'
  DSH_WIN7_RUNTIME_OVERLAY = Join-Path $out 'win7-runtime-overlay'
  DSH_WIN7_PWSH_ARCHIVE = Join-Path $out 'pwsh\PowerShell-7.2.24-win-x64.zip'
  DSH_WIN7_ELECTRON_ARCHIVE = Join-Path $out 'electron-v44.2.0-win32-x64.zip'
}
foreach ($name in $inputs.Keys) {
  if (-not (Test-Path -LiteralPath $inputs[$name])) { throw "$name input is missing: $($inputs[$name])" }
  Set-Item "env:$name" $inputs[$name]
}
$env:DSH_WIN7_PWSH_SHA256 = (Get-Content -Raw "$($inputs.DSH_WIN7_PWSH_ARCHIVE).sha256").Trim()
if (-not $env:DSH_WIN7_UPDATE_URL) { $env:DSH_WIN7_UPDATE_URL = 'https://github.com/factfinding/dsh-win7/releases/latest/download/' }
$env:PATH = (Join-Path $root 'tools\node-v24.21.0-win-x64') + ';' + $env:PATH
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
$env:ELECTRON_SKIP_BINARY_DOWNLOAD = '1'
Push-Location (Join-Path $root 'deepseek-harness')
try {
  corepack pnpm run package:desktop:win:x64:unsigned @args
  if ($LASTEXITCODE -ne 0) { throw "packaging failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
