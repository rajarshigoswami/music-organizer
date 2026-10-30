@echo off
title Sonix Media Organizer
cd /d %~dp0
echo Launching Sonix Media Organizer (Electron Desktop)...
call npm start
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Electron failed or not found. Falling back to Web Mode...
    echo Starting local web server at http://localhost:3000
    start http://localhost:3000
    call npm run web
)
pause
