# Assembles the @dsh-win7/pty-winpty package into out\pty-winpty: shim\pty-winpty sources plus
# winpty 0.4.3's x64 winpty.dll and winpty-agent.exe (out\winpty\extract, from winpty-0.4.3-msvc2015.zip,
# sha256 35a48ece2ff4acdcbc8299d4920de53eb86b1fb41e64d2fe5ae7898931bcee89).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$out = Join-Path $root 'out\pty-winpty'
New-Item -ItemType Directory -Force (Join-Path $out 'bin') | Out-Null
Copy-Item (Join-Path $root 'shim\pty-winpty\index.js'), (Join-Path $root 'shim\pty-winpty\package.json') $out -Force
foreach ($file in 'winpty.dll', 'winpty-agent.exe') {
  Copy-Item (Join-Path $root "out\winpty\extract\x64\bin\$file") (Join-Path $out "bin\$file") -Force
}
Get-ChildItem $out -Recurse -File | ForEach-Object { $_.FullName.Substring($out.Length + 1) }
