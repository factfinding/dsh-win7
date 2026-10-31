# Collects one Windows 7 build's release files for the dsh-win7 GitHub Releases, which also serve as the
# Desktop update feed (DSH_WIN7_UPDATE_URL = .../releases/latest/download/):
#   deepseek-harness-<version>-win7-x64-unsigned.exe            the installer
#   deepseek-harness-<version>-win7-x64-unsigned.exe.blockmap   its block map, for differential downloads
#   nightly.yml                                                 channel file, with the installer's absolute URL
# nightly.yml names the installer by its URL inside the release's own tag directory. The updater derives the
# installed version's block map by replacing the version in that URL, so it resolves to the older release's
# own block map and each release carries only its own files.
# Usage: scripts\prepare-win7-release.ps1 -Version 0.2.1-rc.5 [-Tag dsh-v0.2.1-rc.5-win7.1]
#          [-BaseUrl https://github.com/factfinding/dsh-win7/releases/download/] [-Out out\release\<tag>]
param(
  [Parameter(Mandatory)] [string] $Version,
  [string] $Tag = "dsh-v$Version-win7.1",
  [string] $BaseUrl = 'https://github.com/factfinding/dsh-win7/releases/download/',
  [string] $Artifacts = (Join-Path (Split-Path $PSScriptRoot) 'deepseek-harness\apps\desktop\.desktop-build\targets\win-x64\unsigned-artifacts'),
  [string] $Out = (Join-Path (Split-Path $PSScriptRoot) "out\release\$Tag")
)
$ErrorActionPreference = 'Stop'
if (-not $BaseUrl.EndsWith('/')) { throw 'BaseUrl must end in /' }
$built = "deepseek-harness-$Version-win-x64-unsigned.exe"
$name = "deepseek-harness-$Version-win7-x64-unsigned.exe"
foreach ($file in $built, "$built.blockmap", 'nightly.yml') {
  if (-not (Test-Path -LiteralPath (Join-Path $Artifacts $file))) { throw "missing build output: $file" }
}
$channel = [IO.File]::ReadAllText((Join-Path $Artifacts 'nightly.yml'))
if ($channel -notmatch "(?m)^version: $([regex]::Escape($Version))\r?$") { throw "nightly.yml does not describe version $Version" }

New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item -LiteralPath (Join-Path $Artifacts $built) (Join-Path $Out $name) -Force
Copy-Item -LiteralPath (Join-Path $Artifacts "$built.blockmap") (Join-Path $Out "$name.blockmap") -Force

# The channel file's SHA-512 must be the installer's, or the updater rejects the download.
$stream = [IO.File]::OpenRead((Join-Path $Out $name))
try { $sha512 = [Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash($stream)) } finally { $stream.Dispose() }
if (-not $channel.Contains("sha512: $sha512")) { throw 'nightly.yml SHA-512 does not match the installer' }
$url = "$BaseUrl$Tag/$name"
$rewritten = $channel -replace "(?m)^(\s*-?\s*(?:url|path): )$([regex]::Escape($built))(\r?)$", "`${1}$url`${2}"
if (([regex]::Matches($rewritten, [regex]::Escape($url))).Count -ne 2) { throw 'expected url and path entries for the installer in nightly.yml' }
[IO.File]::WriteAllText((Join-Path $Out 'nightly.yml'), $rewritten, [Text.UTF8Encoding]::new($false))

$sha256 = (Get-FileHash (Join-Path $Out $name) -Algorithm SHA256).Hash.ToLower()
"$sha256  $name" | Set-Content (Join-Path $Out "$name.sha256") -Encoding ascii
"release files for $Tag in ${Out}:"
Get-ChildItem $Out -File | ForEach-Object { "  {0,12:N0}  {1}" -f $_.Length, $_.Name }
"installer sha256 $sha256"
"nightly.yml url  $url"
