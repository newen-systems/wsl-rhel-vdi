# Setting this up without PowerShell — manual steps and MECM packaging

The scripts in `kit/` and `goldimage/` are PowerShell. Plenty of managed Windows
environments do not permit running scripts on endpoints at all.

**You do not need PowerShell for any of this.** The entire WSL build uses native
executables — `dism.exe`, `msiexec.exe`, `wsl.exe`. Everything below is a `cmd.exe`
command or a GUI action. The `.ps1` files are convenience wrappers, not a dependency.

Two routes:

- **Part 1** — do it by hand, per machine (pilots, one-offs, troubleshooting).
- **Part 2** — package it for MECM / SCCM (fleet rollout, post Windows install).

---

## Part 1 — manual setup

### 1.1 Enable the Windows features

**GUI:** Start → *Turn Windows features on or off* → tick **Virtual Machine Platform**
and **Windows Subsystem for Linux** → OK → **reboot**.

**Or `cmd.exe` as Administrator:**

```bat
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
shutdown /r /t 0
```

On virtual desktops the hypervisor must expose nested virtualisation to the VM, or WSL2
reports *"Nested virtualization is not supported"*. The setting name is platform-specific —
check your hypervisor's documentation for exposing hardware virtualisation to a guest.

### 1.2 Install the WSL2 kernel package

Double-click the MSI, or:

```bat
msiexec.exe /i "D:\wsl.2.x.x.x64.msi" /qn /norestart ALLUSERS=1
```

Confirm with `wsl --version`.

### 1.3 Install the distro from a local file

```bat
wsl --install --from-file "D:\rhel-9-x86_64-wsl2.wsl" --no-launch
```

Older `tar.gz` images use the import form:

```bat
mkdir C:\WSL\RHEL-9
wsl --import RHEL-9 C:\WSL\RHEL-9 "D:\rhel-9-x86_64-wsl.tar.gz" --version 2
```

Confirm with `wsl -l -v` — expect the distro listed at `VERSION 2`.

### 1.4 Create `.wslconfig` in Notepad

This file is **per user**, at `%USERPROFILE%\.wslconfig`. Copy `kit/wslconfig.template`,
or paste its contents in Notepad and *Save as* `"%USERPROFILE%\.wslconfig"` **with the
quotes** — without them Notepad appends `.txt`. Save as **ANSI or UTF-8, not UTF-16**.

Apply with `wsl --shutdown`, then start the distro again.

> Use `networkingMode=mirrored` on physical endpoints. On **nested** virtual desktops use
> `networkingMode=nat` instead — mirrored mode can leave the distro with loopback only and
> no `eth0`.

### 1.5 Pin internal names inside the distro

```bat
wsl -d RHEL-9 -u root
```

then, inside the distro:

```bash
printf '%s\n' '192.0.2.10 satellite-01.example.internal satellite-01' >> /etc/hosts
getent hosts satellite-01.example.internal        # must return the address
```

> ⚠ **This does not survive a distro restart on its own.** WSL regenerates `/etc/hosts`
> at every start unless you disable it. Add to `/etc/wsl.conf` inside the distro:
>
> ```ini
> [network]
> generateHosts=false
> generateResolvConf=false
> ```
>
> then `wsl --shutdown` and re-check. The alternative that survives by construction is to
> put the entries in the **Windows** hosts file at
> `%WINDIR%\System32\drivers\etc\hosts` — WSL propagates those into the generated file on
> every start, so no per-distro change is needed.

### 1.6 Register the distro to Satellite

Inside the distro as root:

```bash
# 1. trust the Satellite CA - by IP, so this works before DNS is pinned
curl -skf -o /tmp/ca.rpm https://192.0.2.10/pub/katello-ca-consumer-latest.noarch.rpm
rpm -Uvh /tmp/ca.rpm

# 2. give THIS distro a unique name first.
#    Every distro on a machine inherits the same Windows computer name, so registering
#    a second one overwrites the first one's Satellite host record.
echo "$(hostname)-rhel9" > /etc/hostname

# 3. register
subscription-manager register --org "ExampleOrg" \
  --activationkey "ak-rhel9-example" --force

# 4. verify - run BOTH, they disagree in a useful way
subscription-manager identity
subscription-manager repos --list-enabled
dnf repolist
```

> **`subscription-manager repolist` does not exist** — it prints the usage banner. Use
> `repos --list-enabled` and `dnf repolist`.
>
> A working `dnf repolist` **alone does not prove registration is healthy**: it can serve
> from a cached `redhat.repo` while the server no longer knows the client. If `identity`
> warns that the consumer was deleted from the server, run `subscription-manager clean`
> and register again.

### 1.7 Making it work for every user, without scripts

WSL distros register **per user**. Three options:

1. Each user runs 1.3–1.5 once. Simplest; the image file can live on a read-only share.
2. **Task Scheduler GUI** — *Create Task* → Trigger *At log on* → *Any user* → Action
   `wsl.exe`, arguments `--install --from-file "C:\ProgramData\WSL\distros\<image>.wsl" --no-launch`.
   If you create it from the command line instead, `/RU "BUILTIN\Users"` is **required** —
   without it the task binds to the account that created it and fires for that user only.
3. Bake a default user into the image at build time (`wsl --manage <distro>
   --set-default-user <name>`) so there is no per-user step at all.

---

## Part 2 — MECM / SCCM packaging

Better than the manual path for a fleet, and it sidesteps the script restriction: program
command lines are `cmd.exe` invocations, running in SYSTEM context.

Ready-to-edit scripts are in [`mecm/`](mecm/). Split into **two applications** — they have
different reboot and context needs.

### 2.1 Application 1 — "WSL2 Platform"

| Field | Value |
|---|---|
| Install behaviour | Install for system |
| Logon requirement | Whether or not a user is logged on |
| Install command | `cmd.exe /c install-wsl-platform.cmd` |
| Restart behaviour | Determine behavior based on return codes |
| Return codes | `0` = Success, `3010` = Soft reboot |

The script returns `3010` deliberately. The features need a restart before `wsl.exe` will
start, so the deployment tool should own that reboot — swallowing it makes the *next* step
fail on a machine that never restarted.

**Detection method** — registry, no script:

```
Hive:  HKEY_LOCAL_MACHINE
Key:   SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{WSL MSI ProductCode}
Value: DisplayVersion       Rule: Version >= <the version you shipped>
```

Do **not** detect on the existence of `%WINDIR%\System32\wsl.exe` — an inbox stub is
present on Windows 11 before the MSI is installed, so that rule reports success on every
machine.

### 2.2 Application 2 — "WSL Distro Payload"

Depends on Application 1. Put your `.wsl` / `.tar.gz` files in `mecm/images/` alongside
the script.

| Field | Value |
|---|---|
| Install behaviour | Install for system |
| Install command | `cmd.exe /c stage-wsl-distros.cmd` |
| Dependency | Application 1 |

It copies each image, **verifies the copy by size**, drops `wslconfig.template` and
`import-for-user.cmd` into `C:\ProgramData\WSL\`, and registers an **Active Setup** entry
so each user gets the distro imported at their first logon.

**Detection:** file existence of the staged image **plus** the Active Setup key. The file
alone does not prove the per-user hook is wired.

To re-run the per-user step for profiles that already exist, bump `ACTIVE_SETUP_VER` in
the script and redeploy. That is the supported mechanism — do not delete profiles.

### 2.3 Task-sequence form (OSD)

The same scripts drop into a task sequence as **Run Command Line** steps:

```
1. Run Command Line : cmd.exe /c install-wsl-platform.cmd    (success codes 0 3010)
2. Restart Computer
3. Run Command Line : cmd.exe /c stage-wsl-distros.cmd
```

The restart between the features and any `wsl.exe` call is mandatory.

### 2.4 Gotchas

| Gotcha | Detail |
|---|---|
| **SYSTEM context gives no user a distro** | `wsl --install` registers per user. A SYSTEM install stages files only — Active Setup is what makes it real. This is the most common way this deployment "succeeds" and does nothing. |
| **Surface `3010`, do not swallow it** | returning `0` after enabling features makes the tool report success on a machine that has not rebooted |
| **Content size** | `.wsl` images run from ~100 MB to over 1 GB — check distribution-point replication before a wide deployment |
| **Nested virtualisation** | on virtual desktops the hypervisor must expose it, or the package installs cleanly and WSL still will not start |
| **Detection is not health** | registry and file rules prove the payload landed, not that WSL runs. Pair with a configuration item that runs `wsl -l -v` and checks for a `VERSION 2` line |

### 2.5 What MECM cannot do for you

Satellite registration runs **inside** the distro, so it is not something the deployment
installs directly. Either bake it into the image before packaging, or have
`import-for-user.cmd` call:

```bat
wsl.exe -d RHEL-9 -u root -- /bin/bash /mnt/c/ProgramData/WSL/register.sh
```

See 1.6 for the commands and the unique-hostname requirement.

---

## Appendix — Windows answer file (optional)

[`imagebuild/autounattend.xml.example`](imagebuild/autounattend.xml.example) is a complete
Windows Setup answer file, if you are building the base image yourself rather than
receiving one. Replace every `{{ … }}`.

Three rules worth stating, each of which costs hours when broken:

1. **Keep it pure ASCII.** A UTF-8 em-dash in `FirstLogonCommands` breaks parsing
   **silently** — the commands simply never run.
2. **Ship it at the media root *and* at `\sources\autounattend.xml`.** An answer file at
   the root of a *fixed* disk is not in the documented implicit search order.
3. **It must still parse as XML once staged.** If the copy into the image is truncated or
   corrupt, the OOBE loader fails with `0x80070246`, skips the whole `oobeSystem` pass, and
   the machine parks on *"Windows could not complete the installation"* with no network and
   no remote access. If you apply the image with DISM, verify the staged copy before
   rebooting into it.

If you hit that dialog: `Shift+F10` opens a command prompt.
`reg query "HKLM\SYSTEM\Setup\Status\ChildCompletion"` — `oobeldr.exe = 1` is the wedge.
Replace the answer file with a clean copy and let `windeploy` re-run. **Do not** set
`ChildCompletion` to `3`: that marks the pass complete and skips it, so account setup and
first-logon commands never run and you get a booting but unprovisioned machine.
