# RHEL 9 on WSL2 for Windows VDI — offline, multi-user, Satellite-managed

**What this is:** a proven recipe for adding **offline RHEL 9 under WSL2** to a Windows
VDI image your Windows team already builds. Every VDI user who logs on gets their own
RHEL instance, on the corporate network (mirrored networking), resolving internal DNS,
pulling updates from your **Red Hat Satellite** server. No Microsoft Store, no internet
on the guest.

**What this is not:** a Windows deployment guide. Your existing gold image is the
starting point.

**Total hands-on time:** ~45 min once you have the artifacts. Each numbered step says
how long it takes and what "done" looks like. Do them in order. Don't skip the
✅ checks — every one of them catches a real failure we hit while proving this.

---

## 0. What you need before you start (15 min of collecting, zero thinking)

Collect these into one folder. This folder becomes `C:\ProgramData\WSL-Kit\` on the
gold image.

| # | Artifact | Where from | Example name |
|---|---|---|---|
| 1 | WSL MSI installer (offline) | github.com/microsoft/WSL releases | `wsl.2.7.11.0.x64.msi` |
| 2 | RHEL 9 WSL image | **Section 0b below** — download or build, no Linux box needed | `rhel-9.7-x86_64-wsl.tar.gz` |
| 3 | Your Satellite server's CA consumer URL | `https://<satellite-fqdn>/pub/katello-ca-consumer-latest.noarch.rpm` | — |
| 4 | A Satellite **activation key** whose content view includes RHEL 9 repos | Satellite web UI → Content → Activation Keys | `ak-rhel9-dev` |
| 5 | Your Satellite **organization NAME** (the word, not a number — see gotcha G4) | Satellite web UI → Administer → Organizations | `ExampleOrg` |

**Platform prerequisites** (tell whoever owns the hypervisor):
- The VDI VM needs **nested virtualization** exposed (`vhv.enable = TRUE` on vSphere).
  WSL2 is a VM; without this it degrades or fails.
- Windows 11 22H2 or later on the image (mirrored networking needs it).

✅ **Done when:** one folder holds items 1–2 and you have values for 3–5 written down.

---

## 0b. Get — or build — the RHEL WSL image (no Linux experience needed)

### Path A: download the official image (5 min — do this one)

Red Hat publishes ready-made WSL images. This is exactly what we used.

1. Sign in at **developers.redhat.com** (a free Red Hat Developer account works) or
   your company's **access.redhat.com** portal.
2. Products → Red Hat Enterprise Linux → Downloads → pick the RHEL 9.x release →
   download the file that looks like **`rhel-9.7-x86_64-wsl.tar.gz`** ("WSL image").
3. Check the SHA-256 shown on the download page:
   ```powershell
   Get-FileHash .\rhel-9.7-x86_64-wsl.tar.gz -Algorithm SHA256
   ```

✅ **Done when:** the hash matches and the file sits in your staging folder.

### Path B: build a customized "golden" image — 100% on Windows (20 min)

Use this when you want packages, users, or config **baked into** the image every VDI
user receives. You never leave Windows: import the official image once, change it,
export it. The export IS your custom image.

On any Windows machine with WSL enabled (your build box, not the gold image):

```powershell
# 1. Import the official image as a throwaway build instance
wsl --import RHEL-9-build C:\wsl-build\rhel9 .\rhel-9.7-x86_64-wsl.tar.gz

# 2. Customize inside it (root shell) — examples:
wsl -d RHEL-9-build -u root
#    dnf -y install <tools you want baked in>     (needs step-5 registration first,
#                                                  or a reachable repo)
#    echo -e "[user]\ndefault=vdi" > /etc/wsl.conf # default user, etc.
#    exit

# 3. CRITICAL before export: strip any registration identity (see G10)
wsl -d RHEL-9-build -u root -- subscription-manager clean

# 4. Export = your golden image; then delete the build instance
wsl --terminate RHEL-9-build
wsl --export RHEL-9-build .\rhel-9-golden.tar.gz
wsl --unregister RHEL-9-build
```

Ship `rhel-9-golden.tar.gz` as the shared image in step 2 (adjust the filename in
`Initialize-WSL-User.ps1`).

✅ **Done when:** on the build box, `wsl --import test C:\wsl-build\test .\rhel-9-golden.tar.gz`
gives a working shell — then `wsl --unregister test`.

---

## 1. Enable WSL on the gold image — offline (10 min + 1 reboot)

As admin on the gold image (no internet needed):

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
Restart-Computer
# after reboot:
msiexec /i C:\path\to\wsl.2.7.11.0.x64.msi /qn
```

✅ **Done when:** `wsl --version` prints a WSL version (2.x) and does NOT mention the
Store.

---

## 2. Stage the shared kit — machine-wide, once (5 min)

Everything users need lives in `C:\ProgramData` so it works for **every** user without
per-user downloads:

```text
C:\ProgramData\WSL\distros\rhel-9.7-x86_64-wsl.tar.gz   ← the shared image
C:\ProgramData\WSL-Kit\wslconfig.template               ← networking profile (step 3)
C:\ProgramData\WSL-Kit\satellite.env                    ← Satellite settings (step 5)
C:\ProgramData\WSL-Kit\Initialize-WSL-User.ps1          ← per-user setup (step 4)
C:\ProgramData\WSL-Kit\Configure-RHEL-Satellite.sh      ← in-distro registration (step 5)
```

⚠️ Keep every script **pure ASCII** — a single smart-quote or em-dash pasted from a
wiki breaks PowerShell/cmd parsing in unattended contexts, silently (gotcha G7).

✅ **Done when:** the five paths above exist and `Get-Content` shows no weird characters.

---

## 3. Networking profile — mirrored mode + corporate DNS (5 min)

**Why you care:** WSL's default (NAT) gives instances a private 172.x address and, in
our proof, **no working DNS at all** for internal names. Mirrored mode makes the Linux
side share the Windows host's real network identity — same IP, same L2, reachable and
resolving like any other corporate machine.

`C:\ProgramData\WSL-Kit\wslconfig.template`:

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
localhostForwarding=true

[experimental]
hostAddressLoopback=true
```

**And fix the Windows host's DNS order** (WSL inherits it): the corporate resolver
must come FIRST on the adapter. A public resolver (8.8.8.8, 1.1.1.1) listed first =
internal names randomly fail inside WSL (gotcha G5).

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet0" -ServerAddresses 10.0.0.53
```

✅ **Done when:** `Resolve-DnsName <internal-fqdn>` works on the Windows host.

---

## 4. Per-user setup at logon — the multi-user trick (10 min)

**Why you care:** WSL registrations are **per-user** (they live under each user's
HKCU/`%LOCALAPPDATA%`). One admin installing a distro does nothing for the next user
who logs on. The fix: a logon task that runs a setup script **as the user logging on**.

`Initialize-WSL-User.ps1` must do, in this order:

```powershell
# 1. Personal networking profile (idempotent copy)
Copy-Item C:\ProgramData\WSL-Kit\wslconfig.template "$env:USERPROFILE\.wslconfig" -Force

# 2. Register RHEL for THIS user from the shared image (marker-guarded, offline)
$marker = "$env:LOCALAPPDATA\WSL-Kit\rhel9.done"
if (-not (Test-Path $marker)) {
    wsl.exe --import RHEL-9 "$env:LOCALAPPDATA\WSL\RHEL-9" `
        C:\ProgramData\WSL\distros\rhel-9.7-x86_64-wsl.tar.gz
    New-Item -Force -ItemType File $marker | Out-Null
}

# 3. CRITICAL: restart the WSL VM so the profile from step 1 actually applies
wsl.exe --shutdown
```

Install it as a scheduled task that fires for **every** interactive user:

```powershell
schtasks /Create /TN "WSL-InitUser" /SC ONLOGON /RL LIMITED `
    /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\WSL-Kit\Initialize-WSL-User.ps1"
```

Two hard-won rules:
- **`wsl --shutdown` is not optional** (gotcha G1). The `.wslconfig` is only read when
  the WSL VM starts. An instance launched before the profile landed stays NAT forever
  and looks like "mirrored mode doesn't work".
- **Serialize users** (gotcha G6). Two users initializing concurrently race the WSL
  service. The logon-task model naturally serializes; don't "optimize" it into a
  parallel fan-out.

✅ **Done when:** log on as a fresh test user → open Terminal → `wsl -d RHEL-9` gives a
shell **as that user**, and `ip a` inside shows the **host's** corporate IP (not
172.x). If you see 172.x: `wsl --shutdown`, relaunch, look again.

---

## 5. Point RHEL at Red Hat Satellite (10 min)

`C:\ProgramData\WSL-Kit\satellite.env` — all the site-specific values in ONE file:

```sh
SATELLITE_IP=10.0.0.91
SATELLITE_HOSTNAME=satellite-01
SATELLITE_FQDN=satellite-01.example.internal
SATELLITE_URL=https://satellite-01.example.internal
# Quoted: multi-token values split into bare commands when sourced unquoted
SATELLITE_HOST_ALIASES="satellite.example.internal"
# The Satellite organization NAME — see gotcha G4
SATELLITE_ORG=ExampleOrg
SATELLITE_ACTIVATION_KEY=ak-rhel9-dev
```

`Configure-RHEL-Satellite.sh` (run inside the distro, as root) does four things:

```sh
set -a; . /mnt/c/ProgramData/WSL-Kit/satellite.env; set +a
# 1. /etc/hosts pins (belt-and-braces against resolver hiccups)
echo "$SATELLITE_IP $SATELLITE_FQDN $SATELLITE_HOSTNAME $SATELLITE_HOST_ALIASES" >> /etc/hosts
# 2. Trust the Satellite CA
dnf -y install "$SATELLITE_URL/pub/katello-ca-consumer-latest.noarch.rpm"
# 3. Register with org + activation key
subscription-manager register --org "$SATELLITE_ORG" --activationkey "$SATELLITE_ACTIVATION_KEY"
# 4. Prove it
subscription-manager identity && dnf repolist
```

✅ **Done when:** `subscription-manager identity` prints a consumer ID and
`dnf repolist` lists repos from your content view. Then `dnf update` — if it resolves
packages, **the setup is complete**.

---

## 6. The 60-second acceptance test (run per machine, per user)

```sh
wsl -l -v                      # RHEL-9, VERSION 2, for THIS user
ip a                           # host's corporate IP on eth0 = mirrored is live
getent hosts <internal-fqdn>   # internal DNS resolves inside WSL
subscription-manager identity  # registered consumer
dnf update                     # content flows from Satellite
```

All five pass → ship the image.

---

## Gotchas that cost us real hours (read once, save a day)

| # | Symptom | Cause → Fix |
|---|---|---|
| G1 | "Mirrored mode ignored" — instance has 172.x NAT IP despite correct `.wslconfig` | Profile is read at WSL-VM start only → `wsl --shutdown`, relaunch |
| G2 | No `/etc/resolv.conf` at all inside the distro | dnsTunneling half-applied to an instance started pre-profile → same fix as G1 |
| G3 | Internal names don't resolve in WSL but do on Windows | Public resolver listed before the corporate one on the host adapter → corporate DNS first (step 3) |
| G4 | `subscription-manager register` → HTTP 404 "Couldn't find Organization" | You used the numeric Red Hat portal org id. Satellite wants the org **NAME** (`ExampleOrg`) |
| G5 | Registered fine, but `dnf repolist` is empty | Activation key's content view has no RHEL repos → fix the content view in Satellite, not the client |
| G6 | Random per-user setup failures when several users initialize at once | WSL service races → serialize (one logon task, no parallel fan-out) |
| G7 | Script "does nothing" in unattended context, works when pasted manually | Non-ASCII punctuation (em-dash, smart quotes) in a `.ps1`/`.cmd` → keep kit files pure ASCII |
| G8 | `wsl` warns "Nested virtualization is not supported" | Hypervisor didn't expose VT-x/AMD-V to the VDI VM → platform setting (vSphere `vhv.enable`) |
| G9 | Consumer registers with a NAT IP / odd hostname in Satellite facts | Registration ran before mirrored mode applied → G1 first, then register |
| G10 | Every VDI user shows up in Satellite as the SAME host / registrations overwrite each other | The golden image was exported while registered → `subscription-manager clean` before `wsl --export` (path B step 3); register per-instance at deploy time only |

---

## Provenance

Proven end-to-end 2026-08-07 on a Windows 11 Pro 25H2 VDI template (vSphere, nested
virt on): three users each with their own offline RHEL 9 WSL2 instance, mirrored
networking, internal DNS, registered to a Satellite-compatible content server and pulling updates from a
RHEL 9 content view.
