# Runs at logon AS THE USER (see goldimage\Install-LogonTask.ps1).
# WSL registrations are per-user, so every user needs this once.
# Idempotent: a marker file skips completed work on later logons.

$ErrorActionPreference = 'Continue'

$DistroName = 'RHEL-9'
$SharedImage = 'C:\ProgramData\WSL\distros\rhel-9-golden.tar.gz'
$KitDir     = 'C:\ProgramData\WSL-Kit'

$stateDir = Join-Path $env:LOCALAPPDATA 'WSL-Kit'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$log = Join-Path $stateDir 'initialize.log'
function Log($m) { Add-Content -Path $log -Value ("[{0:u}] {1}" -f (Get-Date), $m) }

# 1. Personal networking profile (mirrored mode + DNS tunneling)
Copy-Item (Join-Path $KitDir 'wslconfig.template') `
    (Join-Path $env:USERPROFILE '.wslconfig') -Force
Log 'wslconfig applied'

# 2. Register the distro for THIS user from the shared image (offline)
$marker = Join-Path $stateDir ($DistroName + '.done')
if (-not (Test-Path $marker)) {
    if (-not (Test-Path $SharedImage)) { Log "missing $SharedImage"; exit 1 }
    wsl.exe --import $DistroName (Join-Path $env:LOCALAPPDATA ('WSL\' + $DistroName)) $SharedImage 2>&1 |
        ForEach-Object { Log $_ }
    if ($LASTEXITCODE -eq 0) {
        New-Item -ItemType File -Force -Path $marker | Out-Null
        Log 'import ok'
    } else {
        Log "import failed rc=$LASTEXITCODE"
        exit 1
    }
}

# 3. Restart the WSL VM so the networking profile actually applies.
#    The profile is only read at WSL-VM start; skipping this leaves the
#    instance on NAT and looks like "mirrored mode does not work".
wsl.exe --shutdown
Log 'done'
exit 0
