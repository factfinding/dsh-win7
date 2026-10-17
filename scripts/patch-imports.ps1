# Renames import DLLs of a PE file in place, e.g. pointing Windows 8+ API sets at dshw7.dll.
# Only the import descriptors' name strings change; a new name must not be longer than the
# old one and is NUL-padded to its length. The bound import directory, which caches the old
# names, is cleared when present.
# Usage: scripts\patch-imports.ps1 -File in.dll -Out out.dll -Rename @{ 'bcryptprimitives.dll' = 'dshw7.dll' }
param(
  [Parameter(Mandatory)] [string] $File,
  [Parameter(Mandatory)] [string] $Out,
  [Parameter(Mandatory)] [hashtable] $Rename
)
$ErrorActionPreference = 'Stop'
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $File))
function U16([int] $o) { [BitConverter]::ToUInt16($bytes, $o) }
function U32([int] $o) { [BitConverter]::ToUInt32($bytes, $o) }

$pe = U32 0x3C
if ((U32 $pe) -ne 0x00004550) { throw "$File is not a PE file" }
$sectionCount = U16 ($pe + 6)
$optionalSize = U16 ($pe + 20)
$optional = $pe + 24
$magic = U16 $optional
$dataDirectories = $optional + $(if ($magic -eq 0x20B) { 112 } else { 96 })
$sections = $optional + $optionalSize

function FileOffset([uint32] $rva) {
  for ($i = 0; $i -lt $sectionCount; $i++) {
    $s = $sections + 40 * $i
    $virtualAddress = U32 ($s + 12); $rawSize = U32 ($s + 16); $rawPointer = U32 ($s + 20)
    $virtualSize = [Math]::Max((U32 ($s + 8)), $rawSize)
    if ($rva -ge $virtualAddress -and $rva -lt $virtualAddress + $virtualSize) { return [int]($rva - $virtualAddress + $rawPointer) }
  }
  throw "RVA 0x$('{0:X}' -f $rva) is outside every section"
}

$importRva = U32 ($dataDirectories + 8)
if ($importRva -eq 0) { throw "$File has no import directory" }
$descriptor = FileOffset $importRva
$renamed = @()
while ((U32 ($descriptor + 12)) -ne 0) {
  $nameOffset = FileOffset (U32 ($descriptor + 12))
  $end = $nameOffset; while ($bytes[$end] -ne 0) { $end++ }
  $name = [Text.Encoding]::ASCII.GetString($bytes, $nameOffset, $end - $nameOffset)
  $target = $Rename.Keys | Where-Object { $_ -ieq $name } | Select-Object -First 1
  if ($target) {
    $new = [Text.Encoding]::ASCII.GetBytes([string]$Rename[$target])
    if ($new.Length -gt $end - $nameOffset) { throw "replacement for $name is longer than the original" }
    for ($i = $nameOffset; $i -lt $end; $i++) { $bytes[$i] = 0 }
    [Array]::Copy($new, 0, $bytes, $nameOffset, $new.Length)
    $renamed += "$name -> $($Rename[$target])"
  }
  $descriptor += 20
}
$missing = $Rename.Keys | Where-Object { $k = $_; -not ($renamed | Where-Object { $_ -like "$k -> *" }) }
if ($missing) { throw "not imported by ${File}: $($missing -join ', ')" }

$boundEntry = $dataDirectories + 11 * 8
if ((U32 $boundEntry) -ne 0) {
  [Array]::Clear($bytes, $boundEntry, 8)
  $renamed += 'bound import directory cleared'
}
[IO.File]::WriteAllBytes($Out, $bytes)
$renamed
