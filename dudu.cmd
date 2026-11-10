@echo off
rem dudu for PowerShell, cmd and the Start menu: runs the dudu next to this file in Git Bash.
rem No folder is written in here: everything is found when it runs, so a user folder with an
rem accent or a space works, wherever dudu is installed.
setlocal
set "DUDU_BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "DUDU_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined DUDU_BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "DUDU_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined DUDU_BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "DUDU_BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined DUDU_BASH if exist "%USERPROFILE%\scoop\apps\git\current\bin\bash.exe" set "DUDU_BASH=%USERPROFILE%\scoop\apps\git\current\bin\bash.exe"
if not defined DUDU_BASH for /f "delims=" %%G in ('where git.exe 2^>nul') do if not defined DUDU_BASH if exist "%%~dpG..\bin\bash.exe" set "DUDU_BASH=%%~dpG..\bin\bash.exe"
if not defined DUDU_BASH echo dudu needs Git for Windows, which was not found. Install it from https://git-scm.com/download/win and run dudu again.
if not defined DUDU_BASH exit /b 1
rem Git Bash wants the path with forward slashes.
set "DUDU_DIR=%~dp0"
set "DUDU_DIR=%DUDU_DIR:\=/%"
rem UTF-8 while dudu runs, so names with accents from Windows tools read right; then back.
set "DUDU_CP="
for /f "tokens=2 delims=:" %%C in ('chcp 2^>nul') do set "DUDU_CP=%%C"
if defined DUDU_CP set "DUDU_CP=%DUDU_CP: =%"
if defined DUDU_CP set "DUDU_CP=%DUDU_CP:.=%"
chcp 65001 >nul 2>&1
rem One line: cmd reads a batch file line by line, and dudu uninstall deletes this file
rem while it runs. What comes after dudu is already read by then.
"%DUDU_BASH%" "%DUDU_DIR%dudu" %* & call set "DUDU_RC=%%ERRORLEVEL%%" & (if defined DUDU_CP chcp %DUDU_CP% >nul 2>&1) & call exit /b %%DUDU_RC%%
