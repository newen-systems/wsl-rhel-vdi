@echo off
REM ============================================================================
REM  Per-user distro import. Invoked by Active Setup at each user's first logon.
REM  WSL distros register PER USER - a SYSTEM-context install gives nobody a
REM  working distro. This script is what makes the deployment actually land.
REM ============================================================================
setlocal EnableExtensions

REM ---- EDIT THESE -----------------------------------------------------------
set DISTRO_DIR=C:\ProgramData\WSL\distros
set IMAGE_1=rhel-9-x86_64-wsl2.wsl
set IMAGE_2=
REM ---------------------------------------------------------------------------

if exist "%DISTRO_DIR%\%IMAGE_1%" wsl.exe --install --from-file "%DISTRO_DIR%\%IMAGE_1%" --no-launch
if not "%IMAGE_2%"=="" if exist "%DISTRO_DIR%\%IMAGE_2%" wsl.exe --install --from-file "%DISTRO_DIR%\%IMAGE_2%" --no-launch

if not exist "%USERPROFILE%\.wslconfig" (
  if exist "C:\ProgramData\WSL\wslconfig.template" copy /y "C:\ProgramData\WSL\wslconfig.template" "%USERPROFILE%\.wslconfig" >nul
)
exit /b 0
