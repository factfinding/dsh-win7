# Generates a module-definition file for a shim DLL that stands in for whole system DLLs
# in one executable's import table: every function the executable imports (static imports,
# from dump-imports.ps1's TSV) from the listed DLLs is forwarded back to that DLL, except
# the ones the shim implements itself. -ForwardTo names another module for a listed DLL, for
# API set names Windows 7 lacks (api-ms-win-core-version-l1-1-0.dll -> version). -Ordinals names the function
# behind an ordinal-only import ('<dll>#<n>' = '<function>'); the shim exports it at that ordinal, forwarded
# to the function's name in the target module, because ordinals differ between the API set and the old DLL.
# Usage: scripts\gen-forward-def.ps1 -Tsv imports.tsv -Library dshlo -Dlls kernel32.dll,user32.dll `
#          -Implemented @{ GetSystemTimePreciseAsFileTime = 'DshGetSystemTimePreciseAsFileTime' } -Out dshlo.def
#          [-ForwardTo @{ 'api-ms-win-mm-time-l1-1-0.dll' = 'winmm' }]
#          [-Ordinals @{ 'api-ms-win-shcore-path-l1-1-0.dll#170' = 'PathIsNetworkPathW' }]
param(
  [Parameter(Mandatory)] [string] $Tsv,
  [Parameter(Mandatory)] [string] $Library,
  [Parameter(Mandatory)] [string[]] $Dlls,
  [Parameter(Mandatory)] [hashtable] $Implemented,
  [Parameter(Mandatory)] [string] $Out,
  [hashtable] $ForwardTo = @{},
  [hashtable] $Ordinals = @{}
)
$ErrorActionPreference = 'Stop'
$wanted = $Dlls | ForEach-Object { $_.ToLower() }
$rows = Get-Content $Tsv | ForEach-Object {
  $section, $dll, $name = $_.Split("`t")
  if ($section -eq 'static' -and $wanted -contains $dll) { [pscustomobject]@{ dll = $dll; name = $name } }
}
$named = @{}
foreach ($key in $Ordinals.Keys) { $named[$key.ToLower()] = $Ordinals[$key] }
$unnamed = $rows | Where-Object { $_.name.StartsWith('#') -and -not $named.ContainsKey("$($_.dll)$($_.name)") }
if ($unnamed) { throw "ordinal imports need a function name in -Ordinals: $(($unnamed | ForEach-Object { "$($_.dll)$($_.name)" }) -join ', ')" }
$duplicates = $rows | Group-Object name | Where-Object { ($_.Group.dll | Sort-Object -Unique).Count -gt 1 }
if ($duplicates) { throw "imported from more than one listed DLL: $(($duplicates.Name) -join ', ')" }
$missing = $Implemented.Keys | Where-Object { $_ -notin $rows.name }
if ($missing) { throw "implemented but not imported: $($missing -join ', ')" }
$unlisted = $ForwardTo.Keys | Where-Object { $_.ToLower() -notin $wanted }
if ($unlisted) { throw "forward target given for a DLL not in -Dlls: $($unlisted -join ', ')" }
$modules = @{}
foreach ($dll in $ForwardTo.Keys) { $modules[$dll.ToLower()] = $ForwardTo[$dll] }

$lines = @("LIBRARY $Library", 'EXPORTS')
foreach ($row in $rows | Sort-Object dll, name -Unique) {
  $module = if ($modules.ContainsKey($row.dll)) { $modules[$row.dll] } else { [IO.Path]::GetFileNameWithoutExtension($row.dll) }
  if ($row.name.StartsWith('#')) {
    $function = $named["$($row.dll)$($row.name)"]
    $lines += "  $function = $module.$function @$($row.name.Substring(1))"
    continue
  }
  $target = if ($Implemented.ContainsKey($row.name)) { $Implemented[$row.name] } else { "$module.$($row.name)" }
  $lines += "  $($row.name) = $target"
}
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$lines | Set-Content $Out -Encoding ascii
"{0}: {1} exports ({2} implemented, {3} forwarded) for {4}" -f $Out, ($lines.Count - 2), $Implemented.Count, ($lines.Count - 2 - $Implemented.Count), ($Dlls -join ', ')
