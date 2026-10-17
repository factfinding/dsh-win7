@echo off
rem Relays the Win7 test VM's host-only network (VMnet1) to api.deepseek.com:443 only. See api-forward.mjs.
"%~dp0..\tools\node-v24.21.0-win-x64\node.exe" "%~dp0api-forward.mjs" %*
