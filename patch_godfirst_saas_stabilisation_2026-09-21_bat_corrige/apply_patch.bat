@echo off
setlocal EnableExtensions
chcp 65001 >nul

set "PATCH_DIR=%~dp0"
set "PATCH_PS1=%PATCH_DIR%apply_patch.ps1"

if not exist "%PATCH_PS1%" (
    echo ERREUR: apply_patch.ps1 est introuvable dans le dossier du patch.
    echo Dossier du patch: %PATCH_DIR%
    pause
    exit /b 1
)

rem Si un chemin est donne en argument, il sera utilise comme point de depart du projet.
rem Sinon, le script demarre depuis le dossier courant.
rem Important: gardez le dossier du patch SEPARE de la racine du projet,
rem par exemple: GODFIRST-SCHOOL-MANAGMENT-SYSTEM-\_patch_godfirst\
if "%~1"=="" (
    set "PROJECT_START=%CD%"
) else (
    set "PROJECT_START=%~1"
)

if not exist "%PROJECT_START%" (
    echo ERREUR: le point de depart projet est introuvable:
    echo %PROJECT_START%
    pause
    exit /b 1
)

echo.
echo Application du patch GODFIRST-SCHOOL-MANAGMENT-SYSTEM-
echo Point de depart projet : %PROJECT_START%
echo Script PowerShell    : %PATCH_PS1%
echo.

pushd "%PROJECT_START%" >nul
if errorlevel 1 (
    echo ERREUR: impossible d'entrer dans le dossier du projet.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PATCH_PS1%"
set "RESULT=%ERRORLEVEL%"

popd >nul

echo.
if not "%RESULT%"=="0" (
    echo Le patch n'a pas ete applique correctement.
    pause
    exit /b %RESULT%
)

echo Patch applique ou deja present.
pause
exit /b 0
