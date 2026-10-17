# Writes a PE file's import table as TSV lines: <static|delay> <dll> <function or #ordinal>.
# Feed the output to check-imports-win7.ps1 inside the Win7 VM.
param(
  [Parameter(Mandatory)] [string] $Exe,
  [Parameter(Mandatory)] [string] $OutTsv
)
$ErrorActionPreference = 'Stop'
$dumpbin = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC' -Recurse -Filter dumpbin.exe |
  Where-Object { $_.FullName -match 'Hostx64\\x64' } | Select-Object -First 1 -ExpandProperty FullName

$dll = $null
$sect = 'static'
$rows = foreach ($l in & $dumpbin /nologo /imports $Exe) {
  # The trailing Summary lists section names, which would otherwise parse as imports.
  if ($l -match '^\s+Summary\s*$') { break }
  if ($l -match 'Section contains the following delay load imports') { $sect = 'delay' }
  if ($l -match '^\s{4}(\S+\.(dll|drv|exe|sys|ocx|cpl))\s*$') { $dll = $Matches[1].ToLower(); continue }
  if (-not $dll) { continue }
  if ($l -match 'Ordinal\s+(\d+)') { "$sect`t$dll`t#$($Matches[1])" }
  elseif ($l -match '^\s+[0-9A-F]+\s+(\S+)\s*$') { "$sect`t$dll`t$($Matches[1])" }
}
$rows | Set-Content $OutTsv -Encoding ascii
"$($rows.Count) imports written to $OutTsv"
