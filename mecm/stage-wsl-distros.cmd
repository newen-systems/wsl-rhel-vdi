@echo off
REM ============================================================================
REM  Distro payload staging - MECM / SCCM Application 2 of 2 (depends on App 1)
REM  Runs as SYSTEM. Copies images machine-wide and wires the per-user import.
REM ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

REM ---- EDIT THESE -----------------------------------------------------------
set DEST=C:\ProgramData\WSL\distros
set ACTIVE_SETUP_GUID={0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0}
set ACTIVE_SETUP_VER=1,0,0,0
REM ---------------------------------------------------------------------------

set LOG=%WINDIR%\Temp\wsl-stage.log
echo ==== %DATE% %TIME% ==== >> "%LOG%"
if not exist "%DEST%" mkdir "%DEST%"
if not exist "C:\ProgramData\WSL" mkdir "C:\ProgramData\WSL"

REM Copy each image and VERIFY by size. A torn copy of a multi-GB image fails
REM silently here and only surfaces as a confusing import error much later.
for %%F in ("%~dp0images\*.wsl" "%~dp0images\*.tar.gz") do (
  if exist "%%~fF" (
    copy /y "%%~fF" "%DEST%\" >> "%LOG%" 2>&1
    set SRCSZ=0
    set DSTSZ=1
    if exist "%%~fF" for %%A in ("%%~fF") do set SRCSZ=%%~zA
    if exist "%DEST%\%%~nxF" for %%A in ("%DEST%\%%~nxF") do set DSTSZ=%%~zA
    if not "!SRCSZ!"=="!DSTSZ!" (
      echo ERROR size mismatch %%~nxF src=!SRCSZ! dst=!DSTSZ! >> "%LOG%"
      exit /b 5
    )
    echo staged %%~nxF !DSTSZ! bytes >> "%LOG%"
  )
)

copy /y "%~dp0wslconfig.template" "C:\ProgramData\WSL\wslconfig.template" >nul 2>&1
copy /y "%~dp0import-for-user.cmd" "C:\ProgramData\WSL\import-for-user.cmd" >nul 2>&1

REM Active Setup runs the stub once per user at first logon - the supported
REM per-user hook. Bump ACTIVE_SETUP_VER to re-run it for existing profiles.
set AS=HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\%ACTIVE_SETUP_GUID%
reg add "%AS%" /ve /t REG_SZ /d "WSL distro import" /f >> "%LOG%" 2>&1
reg add "%AS%" /v StubPath /t REG_SZ /d "cmd.exe /c C:\ProgramData\WSL\import-for-user.cmd" /f >> "%LOG%" 2>&1
reg add "%AS%" /v Version /t REG_SZ /d "%ACTIVE_SETUP_VER%" /f >> "%LOG%" 2>&1

echo staging complete >> "%LOG%"
exit /b 0
