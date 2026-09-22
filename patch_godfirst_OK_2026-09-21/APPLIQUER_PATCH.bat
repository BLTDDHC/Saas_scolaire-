@echo off
setlocal
set "PATCH_PS1=%~dp0APPLIQUER_PATCH.ps1"

if not exist "%PATCH_PS1%" (
  echo ERREUR: APPLIQUER_PATCH.ps1 est introuvable dans ce dossier.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PATCH_PS1%" %*
set "CODE=%ERRORLEVEL%"

if not "%CODE%"=="0" (
  echo.
  echo ECHEC: le patch n'a pas ete applique. Code: %CODE%
  pause
  exit /b %CODE%
)

echo.
echo OK: patch applique et verifie.
pause
exit /b 0
