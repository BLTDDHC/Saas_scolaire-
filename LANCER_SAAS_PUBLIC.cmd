@echo off
title GODFIRST SaaS public - ngrok
echo Ce mode ngrok est temporaire et devra etre retire avant la production.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start_public_saas.ps1"
if errorlevel 1 pause
