# Applies patches\Electron-for-windows-7\v44.2.0 to the synced checkout in e\src.
# Order, following the patch repository's own chromium\apply_patches.bat:
#   1. chromium\<hash>.diff for each line of commit_hashes.txt, LAST line first (the .bat reverses it),
#      with `git apply --ignore-space-change`, checked before applying and stopping at the first failure;
#   2. electron\*.diff in src\electron;
#   3. third_party\electron_node\* in src\third_party\electron_node;
#   4. the two root-level patches (ui\views\win, third_party\nearby) in src;
#   5. our own fixes in win7-fixes\electron\<path under src>\*.patch, in the repository at that path.
# Re-running skips patches whose reverse already applies. Do not run `gclient sync` afterwards: it resets the tree.
param([string] $Src = (Join-Path (Split-Path $PSScriptRoot) 'e\src'))
$ErrorActionPreference = 'Stop'
$patches = Join-Path (Split-Path $PSScriptRoot) 'patches\Electron-for-windows-7\v44.2.0'
$fixes = Join-Path (Split-Path $PSScriptRoot) 'win7-fixes\electron'
$env:GIT_CONFIG_COUNT = '1'; $env:GIT_CONFIG_KEY_0 = 'core.autocrlf'; $env:GIT_CONFIG_VALUE_0 = 'false'

function Apply-One([string] $repo, [string] $patch) {
  $name = Split-Path $patch -Leaf
  git -C $repo apply --check --ignore-space-change $patch 2>$null
  if ($LASTEXITCODE -eq 0) {
    git -C $repo apply --ignore-space-change $patch
    if ($LASTEXITCODE -ne 0) { throw "apply failed after a clean check: $name" }
    return 'applied'
  }
  git -C $repo apply --check --reverse --ignore-space-change $patch 2>$null
  if ($LASTEXITCODE -eq 0) { return 'already' }
  git -C $repo apply --check --verbose --ignore-space-change $patch 2>&1 | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" }
  throw "patch does not apply: $name (in $repo)"
}

$plan = @()
$hashes = Get-Content (Join-Path $patches 'chromium\commit_hashes.txt') | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }
[Array]::Reverse($hashes)
$plan += $hashes | ForEach-Object { [pscustomobject]@{ repo = $Src; patch = Join-Path $patches "chromium\$_.diff" } }
$plan += Get-ChildItem (Join-Path $patches 'electron') -File | Sort-Object Name | ForEach-Object { [pscustomobject]@{ repo = Join-Path $Src 'electron'; patch = $_.FullName } }
$plan += Get-ChildItem (Join-Path $patches 'third_party\electron_node') -File | Sort-Object Name | ForEach-Object { [pscustomobject]@{ repo = Join-Path $Src 'third_party\electron_node'; patch = $_.FullName } }
$plan += Get-ChildItem -Path (Join-Path $patches '*') -File -Include *.patch, *.diff | Sort-Object Name | ForEach-Object { [pscustomobject]@{ repo = $Src; patch = $_.FullName } }
$plan += Get-ChildItem $fixes -Recurse -File -Filter *.patch | Sort-Object FullName | ForEach-Object {
  [pscustomobject]@{ repo = Join-Path $Src $_.DirectoryName.Substring($fixes.Length).TrimStart('\'); patch = $_.FullName }
}

$counts = @{ applied = 0; already = 0 }
$index = 0
foreach ($step in $plan) {
  $index++
  $result = Apply-One $step.repo $step.patch
  $counts[$result]++
  $shown = if ($step.patch.StartsWith($fixes)) { 'win7-fixes\electron' + $step.patch.Substring($fixes.Length) } else { $step.patch.Substring($patches.Length + 1) }
  Write-Host ("[{0}/{1}] {2,-8} {3}" -f $index, $plan.Count, $result, $shown)
}
"done: $($counts.applied) applied, $($counts.already) already applied, $($plan.Count) total"
