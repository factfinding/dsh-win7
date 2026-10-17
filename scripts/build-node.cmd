@echo off
rem Builds the Win7-patched Node.js in node\ (branch win7) with vcbuild.bat.
rem Output: node\out\Release\node.exe and node\Release\node-v*-win-x64.zip.
rem Extra arguments are passed to vcbuild.bat (e.g. noprojgen for rebuilds).
setlocal
rem vcbuild's package step calls 7z, which is installed but not on PATH.
set "PATH=%PATH%;%ProgramFiles%\7-Zip"
rem Claude Code's shells set this, which stops cmd from running vcbuild.bat and
rem its helper scripts from the current directory.
set NoDefaultCurrentDirectoryInExePath=
rem vcbuild runs msbuild with /m:2 and relies on /MP, which clang-cl ignores, so
rem only ~2 files compile at once. MultiToolTask schedules clang-cl in parallel.
rem 12 leaves memory for the Win7 VM (V8 files can take several hundred MB each).
if not defined msbuild_args set "msbuild_args=/p:UseMultiToolTask=true /p:EnforceProcessCountAcrossBuilds=true /p:CL_MPCount=12"
cd /d "%~dp0..\node" || exit /b 1
call vcbuild.bat release x64 package %*
