# Section 0b path B: build a customized golden WSL image, entirely on Windows.
# Run on a build box with WSL enabled (NOT the gold image).
# Import official image -> customize -> strip identity -> export.

# ---- EDIT THESE -------------------------------------------------------------
$OfficialImage = 'C:\Staging\rhel-9.7-x86_64-wsl.tar.gz'  # section 0b path A
$GoldenOut     = 'C:\Staging\rhel-9-golden.tar.gz'        # what you will ship
$BuildName     = 'RHEL-9-build'
$BuildDir      = 'C:\wsl-build\rhel9'
$DefaultUser   = 'vdi'                                     # default login inside the distro
$BakedPackages = @()                                       # e.g. @('git','vim','python3')
# ------------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

wsl.exe --import $BuildName $BuildDir $OfficialImage
if ($LASTEXITCODE -ne 0) { throw 'import failed' }

# Default user for everyone who receives this image
wsl.exe -d $BuildName -u root -- sh -c "printf '[user]\ndefault=$DefaultUser\n' > /etc/wsl.conf; id $DefaultUser >/dev/null 2>&1 || useradd -m $DefaultUser"

# Optional baked packages: needs a reachable repo (register first, or use a
# temporary network). Skipped when the list is empty.
if ($BakedPackages.Count -gt 0) {
    $pkgs = $BakedPackages -join ' '
    wsl.exe -d $BuildName -u root -- sh -c "dnf -y install $pkgs"
    if ($LASTEXITCODE -ne 0) { throw 'package install failed' }
}

# CRITICAL: never ship a registered identity. Exported clones would collide as
# the same host on Satellite (every user overwrites the same consumer).
wsl.exe -d $BuildName -u root -- sh -c "command -v subscription-manager >/dev/null && subscription-manager clean || true"

wsl.exe --terminate $BuildName
wsl.exe --export $BuildName $GoldenOut
wsl.exe --unregister $BuildName

Write-Host "Golden image: $GoldenOut"
Write-Host "Smoke test:  wsl --import golden-test C:\wsl-build\test $GoldenOut ; wsl -d golden-test -- cat /etc/os-release ; wsl --unregister golden-test"
