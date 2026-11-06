@echo off
rem Starts DeepSeek Harness Desktop with a DevTools port on 127.0.0.1 and runs win7-gpu-check.mjs with
rem Desktop's own Node to report whether it renders with the GPU. Quit Desktop first from its tray icon:
rem only one instance runs, and a running one ignores the port. Afterwards quit Desktop and start it
rem normally, so the port does not stay open. Keep both files in the same directory. No labels here:
rem a copy downloaded from GitHub has LF line ends, where cmd.exe cannot rely on goto.
setlocal
set "APP=%LOCALAPPDATA%\Programs\DeepSeek Harness\DeepSeek Harness.exe"
if not exist "%APP%" set "APP=%ProgramFiles%\DeepSeek Harness\DeepSeek Harness.exe"
set PORT=9333
set ELECTRON_RUN_AS_NODE=
rem Without this Desktop attaches to this console and prints its UTF-8 log lines, garbled under GBK.
set ELECTRON_NO_ATTACH_CONSOLE=1
if exist "%APP%" (
  start "" "%APP%" --remote-debugging-port=%PORT%
  echo Waiting 30 seconds for the window and its GPU process...
  ping -n 31 127.0.0.1 > nul
  set ELECTRON_RUN_AS_NODE=1
  "%APP%" "%~dp0win7-gpu-check.mjs" %PORT%
  echo.
  echo Now quit Desktop from its tray icon and start it normally.
) else (
  echo DeepSeek Harness.exe not found.
)
pause