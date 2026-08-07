@echo off
REM ============================================================================
REM  WSL2 platform install - MECM / SCCM Application 1 of 2
REM  Runs as SYSTEM. Pure cmd - no PowerShell required anywhere in this package.
REM  Return codes: 0 = success, 3010 = success + reboot required (see below).
REM ============================================================================
setlocal EnableExtensions

REM ---- EDIT THESE -----------------------------------------------------------
set WSL_MSI=wsl.2.6.1.0.x64.msi
REM ---------------------------------------------------------------------------

set LOG=%WINDIR%\Temp\wsl-platform.log
echo ==== %DATE% %TIME% ==== >> "%LOG%"

dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >> "%LOG%" 2>&1
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >> "%LOG%" 2>&1

if not exist "%~dp0%WSL_MSI%" (
  echo ERROR: %WSL_MSI% not found beside this script >> "%LOG%"
  exit /b 2
)

msiexec.exe /i "%~dp0%WSL_MSI%" /qn /norestart ALLUSERS=1 /L*v "%WINDIR%\Temp\wsl-msi.log"
set RC=%ERRORLEVEL%
echo msiexec rc=%RC% >> "%LOG%"

if not "%RC%"=="0" if not "%RC%"=="3010" exit /b %RC%

REM The Windows features require a restart before wsl.exe will start. Return 3010
REM so the deployment tool owns the reboot; swallowing it makes the NEXT step fail
REM on a machine that never restarted.
exit /b 3010
