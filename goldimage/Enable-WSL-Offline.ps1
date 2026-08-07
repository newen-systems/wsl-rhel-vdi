# Step 1: enable WSL on the gold image, fully offline. Run as admin.
# A reboot is required between the feature enable and the MSI install;
# run the script twice (it resumes where it left off).

# ---- EDIT THESE -------------------------------------------------------------
$WslMsi = 'C:\Staging\wsl.2.7.11.0.x64.msi'   # from github.com/microsoft/WSL releases
# ------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
$pending = $features | Where-Object {
    (Get-WindowsOptionalFeature -Online -FeatureName $_).State -ne 'Enabled'
}

if ($pending) {
    foreach ($f in $pending) {
        dism.exe /online /enable-feature /featurename:$f /all /norestart
    }
    Write-Host 'Features enabled. REBOOT, then run this script again.'
    exit 0
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue) -or
    -not (wsl.exe --version 2>$null)) {
    Start-Process msiexec.exe -ArgumentList "/i `"$WslMsi`" /qn" -Wait
}

wsl.exe --version
Write-Host 'Done when the line above shows a WSL 2.x version with no Store mention.'
