@echo off
rem dudu setup for Windows: download this file and double-click it. It runs the same
rem installer as the PowerShell command in the README, and waits so you can read the result.
title dudu
echo.
echo  Installing dudu...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex"
echo.
pause
