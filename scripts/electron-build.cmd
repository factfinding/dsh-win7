@echo off
rem Builds Electron v44.2.0 for Windows 7 in e\src\out\Release and packs out\Release\dist.zip, which has the
rem layout of the official electron-v44.2.0-win32-x64.zip. Run after electron-sync.cmd and
rem apply-electron-win7-patches.ps1. gn args come from scripts\electron-release.gn; gn gen runs again only
rem when that file changed. ELECTRON_JOBS sets the number of local compile jobs (default 12 of 16 CPUs, to
rem stay within 23 GB of RAM). Extra arguments go to autoninja.
setlocal
call "%~dp0electron-env.cmd"
if not defined ELECTRON_JOBS set ELECTRON_JOBS=12
cd /d "%ELECTRON_ROOT%\src" || exit /b 1
if not exist out\Release mkdir out\Release
fc /b "%~dp0electron-release.gn" out\Release\args.gn > nul 2>&1
if errorlevel 1 (
  copy /y "%~dp0electron-release.gn" out\Release\args.gn > nul || exit /b 1
  call gn gen out\Release || exit /b 1
)
call autoninja -C out\Release -j %ELECTRON_JOBS% electron:electron_dist_zip %*
