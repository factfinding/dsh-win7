# Generates a module-definition file for a shim DLL that stands in for whole system DLLs
# in one executable's import table: every function the executable imports (static imports,
# from dump-imports.ps1's TSV) from the listed DLLs is forwarded back to that DLL, except
# the ones the shim implements itself.
# Usage: scripts\gen-forward-def.ps1 -Tsv imports.tsv -Library dshlo -Dlls kernel32.dll,user32.dll `
#          -Implemented @{ GetSystemTimePreciseAsFileTime = 'DshGetSystemTimePreciseAsFileTime' } -Out dshlo.def
param(
  [Parameter(Mandatory)] [string] $Tsv,
  [Parameter(Mandatory)] [string] $Library,
  [Parameter(Mandatory)] [string[]] $Dlls,
  [Parameter(Mandatory)] [hashtable] $Implemented,
  [Parameter(Mandatory)] [string] $Out
)
$ErrorActionPreference = 'Stop'
$wanted = $Dlls | ForEach-Object { $_.ToLower() }
$rows = Get-Content $Tsv | ForEach-Object {
  $section, $dll, $name = $_.Split("`t")
  if ($section -eq 'static' -and $wanted -contains $dll) { [pscustomobject]@{ dll = $dll; name = $name } }
}
$ordinals = $rows | Where-Object { $_.name.StartsWith('#') }
if ($ordinals) { throw "ordinal imports cannot be forwarded by name: $(($ordinals | ForEach-Object { "$($_.dll)!$($_.name)" }) -join ', ')" }
$duplicates = $rows | Group-Object name | Where-Object { ($_.Group.dll | Sort-Object -Unique).Count -gt 1 }
if ($duplicates) { throw "imported from more than one listed DLL: $(($duplicates.Name) -join ', ')" }
$missing = $Implemented.Keys | Where-Object { $_ -notin $rows.name }
if ($missing) { throw "implemented but not imported: $($missing -join ', ')" }

$lines = @("LIBRARY $Library", 'EXPORTS')
foreach ($row in $rows | Sort-Object dll, name -Unique) {
  $target = if ($Implemented.ContainsKey($row.name)) { $Implemented[$row.name] } else { "$([IO.Path]::GetFileNameWithoutExtension($row.dll)).$($row.name)" }
  $lines += "  $($row.name) = $target"
}
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$lines | Set-Content $Out -Encoding ascii
"{0}: {1} exports ({2} implemented, {3} forwarded) for {4}" -f $Out, ($lines.Count - 2), $Implemented.Count, ($lines.Count - 2 - $Implemented.Count), ($Dlls -join ', ')
