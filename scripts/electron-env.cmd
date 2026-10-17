@echo off
rem Environment for the Electron 44.2.0 (Chromium 152) Win7 build. "call" it from other scripts.
rem depot_tools and the official Node 24 go first on PATH; the local VS 2022 is used instead of
rem Google's internal toolchain. Git settings are overridden through GIT_CONFIG_* so the system-level
rem core.autocrlf=true does not convert the checkout to CRLF; nothing in the global git config changes.
set "DSH_WIN7_ROOT=%~dp0.."
for %%i in ("%DSH_WIN7_ROOT%") do set "DSH_WIN7_ROOT=%%~fi"
set "ELECTRON_ROOT=%DSH_WIN7_ROOT%\e"
set "PATH=%DSH_WIN7_ROOT%\depot_tools;%DSH_WIN7_ROOT%\tools\node-v24.21.0-win-x64;%PATH%"
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
set "vs2022_install=C:\Program Files\Microsoft Visual Studio\2022\Community"
set GIT_CONFIG_COUNT=3
set GIT_CONFIG_KEY_0=core.autocrlf
set GIT_CONFIG_VALUE_0=false
set GIT_CONFIG_KEY_1=core.longpaths
set GIT_CONFIG_VALUE_1=true
set GIT_CONFIG_KEY_2=core.filemode
set GIT_CONFIG_VALUE_2=false
rem Claude Code's shells set this; depot_tools' .bat wrappers call helpers from the current directory.
set NoDefaultCurrentDirectoryInExePath=
