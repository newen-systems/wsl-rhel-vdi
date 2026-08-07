# Step 4: make per-user WSL setup run at every interactive logon. Run as admin.
# WSL registrations are per-user; this task runs the kit's initializer as
# whichever user logs on. The logon-task model also serializes users, which
# matters: concurrent initializations race the WSL service.

# ---- EDIT THESE -------------------------------------------------------------
$TaskName  = 'WSL-InitUser'
$ScriptPath = 'C:\ProgramData\WSL-Kit\Initialize-WSL-User.ps1'
# ------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

schtasks /Create /F /TN $TaskName /SC ONLOGON /RL LIMITED `
    /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath"

schtasks /Query /TN $TaskName
Write-Host 'Done: log on as a fresh test user and check wsl -l -v shows the distro.'
