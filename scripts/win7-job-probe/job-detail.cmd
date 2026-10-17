@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\dsh-test\job-detail.ps1 < nul > C:\dsh-test\job-detail.txt 2>&1