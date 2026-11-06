@echo off
title PulseGuard Companion App Server
cd /d "%~dp0"
echo ========================================================
echo        PulseGuard - Vitals Watch Companion App
echo ========================================================
echo.
echo Starting local proxy server on port 8080...
echo Opening app in your default browser...
start http://localhost:8080
python server.py
pause
