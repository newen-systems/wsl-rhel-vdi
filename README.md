# RHEL 9 on WSL2 for Windows VDI — offline, multi-user, Satellite-managed

**What this is:** a proven recipe for adding **offline RHEL 9 under WSL2** to a Windows
VDI image your Windows team already builds. Every VDI user who logs on gets their own
RHEL instance, on the corporate network (mirrored networking), resolving internal DNS,
pulling updates from your **Red Hat Satellite** server. No Microsoft Store, no internet
on the guest.

**What this is not:** a Windows deployment guide. Your existing gold image is the
starting point.

**Repo layout — every script is ready to download and edit** (variables live in an
`---- EDIT THESE ----` block at the top of each file):

```text
kit/          -> copy to C:\ProgramData\WSL-Kit\ on the gold image
  wslconfig.template            networking profile every user receives
  Initialize-WSL-User.ps1       per-user setup, runs at logon
  register-satellite.sh.example paste your Satellite-generated command here
goldimage/    -> run ON the gold image while building it
  Enable-WSL-Offline.ps1        step 1
  Set-CorporateDns.ps1          step 3
  Install-LogonTask.ps1         step 4
imagebuild/   -> run on a separate Windows build box
  Build-GoldenImage.ps1         section 0b path B
```

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
| 3 | A **registration command** generated in Satellite | Satellite web UI → Hosts → Register Host (pick org, activation key, set a generous token lifetime) | one `curl … \| bash` line |
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

On any Windows machine with WSL enabled (your build box, not the gold image): edit
the variable block at the top of **`imagebuild/Build-GoldenImage.ps1`** (image paths,
default user, packages to bake in) and run it. It imports the official image,
applies your customizations, strips any registration identity (G10), and exports
your golden image. Ship the export as the shared image in step 2 (match the filename
in `kit/Initialize-WSL-User.ps1`).

✅ **Done when:** on the build box, `wsl --import test C:\wsl-build\test .\rhel-9-golden.tar.gz`
gives a working shell — then `wsl --unregister test`.

---

## 1. Enable WSL on the gold image — offline (10 min + 1 reboot)

As admin on the gold image (no internet needed): edit the MSI path at the top of
**`goldimage/Enable-WSL-Offline.ps1`** and run it. It enables the two Windows
features, tells you to reboot, and on the second run installs the WSL MSI.

✅ **Done when:** `wsl --version` prints a WSL version (2.x) and does NOT mention the
Store.

---

## 2. Stage the shared kit — machine-wide, once (5 min)

Everything users need lives in `C:\ProgramData` so it works for **every** user without
per-user downloads. Copy this repo's `kit/` folder to `C:\ProgramData\WSL-Kit\` and
drop your image beside it:

```text
C:\ProgramData\WSL\distros\rhel-9.7-x86_64-wsl.tar.gz   ← the shared image
C:\ProgramData\WSL-Kit\wslconfig.template               ← networking profile (step 3)
C:\ProgramData\WSL-Kit\Initialize-WSL-User.ps1          ← per-user setup (step 4)
C:\ProgramData\WSL-Kit\register-satellite.sh            ← registration command (step 5)
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

The profile ships as **`kit/wslconfig.template`** (mirrored mode + DNS tunneling,
already correct — no edits needed for most sites).

**And fix the Windows host's DNS order** (WSL inherits it): the corporate resolver
must come FIRST on the adapter. A public resolver (8.8.8.8, 1.1.1.1) listed first =
internal names randomly fail inside WSL (gotcha G5). Edit the resolver list at the
top of **`goldimage/Set-CorporateDns.ps1`** and run it — it sets the order and
proves an internal name resolves before letting you continue.

✅ **Done when:** `Resolve-DnsName <internal-fqdn>` works on the Windows host.

---

## 4. Per-user setup at logon — the multi-user trick (10 min)

**Why you care:** WSL registrations are **per-user** (they live under each user's
HKCU/`%LOCALAPPDATA%`). One admin installing a distro does nothing for the next user
who logs on. The fix: a logon task that runs a setup script **as the user logging on**.

**`kit/Initialize-WSL-User.ps1`** does three things in order: copies the networking
profile into the user's own home, imports the shared image as that user's personal
instance (marker-guarded so later logons skip it), then runs `wsl --shutdown` so the
profile applies. Edit the distro name and image path at the top of the file.

Install the trigger with **`goldimage/Install-LogonTask.ps1`** — one scheduled task
that fires for every interactive user.

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

Satellite does the heavy lifting here — you don't hand-configure anything on the
client. Use **global registration**:

1. In the Satellite web UI: **Hosts → Register Host**.
2. Pick your **organization**, the **activation key** from step 0 (its content view
   must include RHEL 9 repos), and set the token lifetime long enough for your
   rollout window.
3. Satellite generates a one-line command (a `curl … | bash`). Paste it into
   **`kit/register-satellite.sh.example`** and save it on the image as
   `C:\ProgramData\WSL-Kit\register-satellite.sh` (the example file shows exactly
   where it goes).

Run it inside the distro (root shell):

```sh
bash /mnt/c/ProgramData/WSL-Kit/register-satellite.sh
# then prove it:
subscription-manager identity && dnf repolist
```

That single command installs the Satellite CA trust, registers the host to your
org with the activation key, and enables the content-view repos — no manual CA
RPMs, no hand-written config.

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
