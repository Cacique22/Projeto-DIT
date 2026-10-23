@echo off
title TESTES AUTOMATIZADOS - ESTACAO DIT
color 0A
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Run-Tests.ps1"
pause
