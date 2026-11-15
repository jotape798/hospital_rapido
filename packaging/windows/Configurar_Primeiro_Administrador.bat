@echo off
setlocal
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0iniciar_ubs_rapida.ps1" -ConfigurarAdministrador
exit /b %ERRORLEVEL%
