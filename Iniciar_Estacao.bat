@echo off
title ESTACAO DE INGESTAO DIT - BACKUP SEGURO
color 0B
echo ========================================================
echo   INICIANDO ESTACAO DE INGESTAO DIT - BACKUP SEGURO
echo ========================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\Start-Station.ps1"
pause
