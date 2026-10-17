# Builds ripgrep (ripgrep\, tag 15.0.0, the version @vscode/ripgrep 1.18.0 ships) for Windows 7.
# x86_64-win7-windows-msvc is a tier 3 target, so std is built from source with -Z build-std.
# Uses the stable toolchain's rust-src (RUSTC_BOOTSTRAP=1 unlocks -Z on stable): nightly
# 2026-10-15 broke std for win7 (is_console is cfg'd out for target_vendor = "win7").
# Matches the official release build: release-lto profile, pcre2 feature, static CRT.
# Output: out\ripgrep-target\x86_64-win7-windows-msvc\release-lto\rg.exe
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$env:PATH = "$HOME\.cargo\bin;" + $env:PATH
$env:RUSTC_BOOTSTRAP = '1'
$env:RUSTFLAGS = '-C target-feature=+crt-static'
$env:CARGO_TARGET_DIR = Join-Path $root 'out\ripgrep-target'
Push-Location (Join-Path $root 'ripgrep')
try {
  cargo +stable build --profile release-lto -Z build-std=std,panic_abort --target x86_64-win7-windows-msvc --features pcre2
  if ($LASTEXITCODE -ne 0) { throw "cargo exited with $LASTEXITCODE" }
} finally {
  Pop-Location
}
