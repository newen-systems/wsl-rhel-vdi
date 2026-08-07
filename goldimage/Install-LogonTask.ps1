# Step 4: make per-user WSL setup run at every interactive logon. Run as admin.
# WSL registrations are per-user; this task runs the kit's initializer as
# whichever user logs on. The logon-task model also serializes users, which
# matters: concurrent initializations race the WSL service.

# ---- EDIT THESE -------------------------------------------------------------
$TaskName  = 'WSL-InitUser'
$ScriptPath = 'C:\ProgramData\WSL-Kit\Initialize-WSL-User.ps1'
# ------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

# /RU "BUILTIN\Users" is REQUIRED and is the whole point of this step.
# Without it, schtasks binds an ONLOGON task to the account that created it - so the
# task fires for the image builder and for nobody else. The image then tests fine for
# whoever built it and silently does nothing for every real user.
schtasks /Create /F /TN $TaskName /SC ONLOGON /RU "BUILTIN\Users" /RL LIMITED `
    /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath"

schtasks /Query /TN $TaskName
Write-Host 'Done. VERIFY AS A DIFFERENT USER: log on as a fresh test account and run'
Write-Host '  wsl -l -v'
Write-Host 'Checking it only as the builder cannot detect a missing /RU.'
