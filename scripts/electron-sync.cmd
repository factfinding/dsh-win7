@echo off
rem Fetches Electron v44.2.0 and its pinned Chromium (152.0.7977.76) into e\ without git history.
rem The Electron DEPS hooks apply Electron's own Chromium patches and download clang/gn/node deps.
rem The Win7 patches (patches\Electron-for-windows-7\v44.2.0) are applied afterwards, separately.
rem e\.gclient is always replaced by scripts\electron.gclient (custom_deps excludes the updater binaries).
rem Re-running resumes an interrupted sync.
rem Electron's DEPS pins src and electron_node by tag name. Once a checkout exists, gclient only skips its fetch
rem when the revision is a sha (gclient_scm.py update: IsValidRevision(sha_only=True)), so a tag makes every
rem re-sync run "git fetch origin" without --depth, which pulls Chromium's whole history (20+ GB). The same
rem commits are pinned here by sha: 152.0.7977.76 and v24.20.0^{} (checked with git ls-remote).
setlocal
call "%~dp0electron-env.cmd"
if not exist "%ELECTRON_ROOT%" mkdir "%ELECTRON_ROOT%"
copy /y "%~dp0electron.gclient" "%ELECTRON_ROOT%\.gclient" > nul || exit /b 1
cd /d "%ELECTRON_ROOT%" || exit /b 1
call gclient sync --revision src/electron@refs/tags/v44.2.0 ^
  --revision src@0d89dfa2dd7c1ec4b8a14b9f303f887bb63b6174 ^
  --revision src/third_party/electron_node@71b8b174857e25106d39b61a9e6f30d927da8b01 ^
  --no-history --shallow -j 8 %*
