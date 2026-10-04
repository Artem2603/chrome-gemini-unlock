@echo off
setlocal
title Chrome Gemini Unlock

if not exist "%~dp0chrome-gemini-unlock.ps1" (
    echo chrome-gemini-unlock.ps1 was not found next to this file.
    echo Extract the whole ZIP archive and run chrome-gemini-unlock.bat again.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0chrome-gemini-unlock.ps1" %*
set "rc=%errorlevel%"
echo.
pause
exit /b %rc%
