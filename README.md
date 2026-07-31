# restarting

[![Stack](https://skillicons.dev/icons?i=linux,bash,git,github,vscode,docker,py,rust,ruby,nodejs,latex,postgres,sqlite&perline=13)](https://skillicons.dev)

A short repository designed to help me quickly acclimate when I need to reinstall my Linux distro, which is typically [Pop!_OS](https://system76.com/pop/).

Targets Pop!_OS 24.04 on a Dell XPS 13 Plus 9315.

## Usage

```bash
git clone https://github.com/<you>/restarting.git
cd restarting
./restart.sh
```

Then reboot, and pick the HWE kernel in rEFInd. See [Boot and kernel](#boot-and-kernel) for why that matters.

`restart.sh` is not `set -e`, on purpose: the sections are independent, so one dead repo will not abort the whole run. Re-running it is safe; the `.bashrc` edits are guarded against duplication.

## Files

| File | Purpose |
|---|---|
| `restart.sh` | The whole setup, top to bottom |
| `refind-default-hwe.sh` | Kernel postinst hook keeping rEFInd on a webcam-capable kernel |

## Repositories added

[![Repos](https://skillicons.dev/icons?i=docker,ubuntu&perline=2)](https://skillicons.dev)

| Repo | For |
|---|---|
| `download.docker.com` | Docker CE, pinned to `noble` since Pop's codename is its own |
| `repo.protonvpn.com` | Proton VPN, via their release `.deb` |
| `updates.signal.org` | Signal Desktop |
| `ppa:oem-solutions-group/intel-ipu6` | Intel IPU6 camera HAL |
| `ppa:rodsmith/refind` | rEFInd bootloader. Commented out; install it by hand when setting up dual boot |
| Spotify | Commented out; the flatpak is used instead |

All added with `--no-update`, then a single `apt update` covers them. `add-apt-repository` otherwise runs its own update each time.

## apt packages

**Desktop apps**

`code` `git-all` `gh` `mpv` `audacity` `qbittorrent` `thunderbird` `proton-vpn-gnome-desktop` `signal-desktop` `steam` `zoom` `cockatrice` `curseforge`

**GNOME**

`gnome-tweaks` `gnome-shell-extension-manager` `gnome-shell-extensions`

**CLI and system**

`adb` `imagemagick` `ffmpegthumbnailer` `sqlite3` `rsync` `locate` `openssh-server` `smartmontools` `ntfs-3g` `tlp` `tlp-rdw`

`refind` is commented out, since installing a bootloader is a deliberate step rather than something to run unattended. Uncomment both it and its PPA when setting up dual boot.

**Build deps for ruby-build**

`autoconf` `bison` `build-essential` `libssl-dev` `libyaml-dev` `libreadline6-dev` `zlib1g-dev` `libncurses5-dev` `libffi-dev` `libgdbm-dev` `libdb-dev`

## Toolchains

[![Toolchains](https://skillicons.dev/icons?i=py,rust,ruby,nodejs,npm&perline=5)](https://skillicons.dev)

All per-user installs under `$HOME`, not apt, each with a guarded `~/.bashrc` hook. Without the hook none of them are on `PATH` in a new shell.

| Tool | Language | Installs to |
|---|---|---|
| `uv` | Python | `~/.local/bin` |
| `rustup` | Rust | `~/.cargo` |
| `elan` | Lean | `~/.elan` |
| `nvm` | Node | `~/.nvm`, then `nvm install --lts` |
| `rbenv` + `ruby-build` | Ruby | `~/.rbenv`, then `gem install bundler jekyll` |

Note `rbenv init` shadows the system `/usr/bin/ruby`, so `jekyll` and `bundler` come from `gem` under rbenv rather than apt. Installing them via apt would give you packages that never actually run.

## LaTeX

[![LaTeX](https://skillicons.dev/icons?i=latex,vscode&perline=2)](https://skillicons.dev)

`latexmk` `biber` `chktex` `texlive-latex-recommended` `texlive-latex-extra` `texlive-fonts-recommended` `texlive-fonts-extra` `texlive-science` `texlive-pictures` `texlive-extra-utils`

The VS Code LaTeX Workshop extension shells out to `latexmk` by default, uses `latexindent` (in `texlive-extra-utils`) for formatting, and `chktex` for linting. `texlive-full` also works but is roughly 6 GB; the above is the useful subset.

## Flatpaks

[![Flatpak apps](https://skillicons.dev/icons?i=discord,obsidian,postman&perline=3)](https://skillicons.dev)

| Category | Apps |
|---|---|
| Chat | Discord |
| Media | Spotify, Foliate |
| Creative | Krita, Obsidian |
| Dev | Postman |
| Backups | Pika Backup |
| Games and emulation | PCSX2, Dolphin |

## VS Code extensions

[![Editor](https://skillicons.dev/icons?i=vscode,py,rust,docker,latex,github&perline=6)](https://skillicons.dev)

Not scripted. Settings Sync restores them on first sign-in.

The one thing it cannot restore is the toolchain an extension shells out to. LaTeX Workshop is the case that bites: the extension syncs fine, but without `latexmk` and friends from the [LaTeX](#latex) section it silently has nothing to build with.

## Docker and Jellyfin

[![Docker](https://skillicons.dev/icons?i=docker,postgres&perline=2)](https://skillicons.dev)

`docker-ce` `docker-ce-cli` `containerd.io` `docker-buildx-plugin` `docker-compose-plugin`

The service is enabled, and `$USER` is added to the `docker` group so it works without `sudo`. That needs a re-login (or `newgrp docker`) to take effect.

Jellyfin runs as a container, not an apt package. `compose.yaml` lives in `~/jellyfin` and is committed separately. It bind-mounts `/mnt/media` read-only and needs `/dev/dri` for hardware transcoding, so the script also creates `/mnt/media` and adds the fstab entry for the Seagate drive. That UUID is specific to the physical disk; re-check with `blkid` if it is ever replaced.

## Webcam

The Intel IPU6 camera (`ov01a10`) is a MIPI sensor, not USB, and runs through Intel's HAL rather than libcamera:

```
ov01a10 -> intel_ipu6_isys + intel_ipu6_psys (kernel)
        -> libcamhal / icamerasrc -> v4l2-relayd -> v4l2loopback
        -> /dev/video0 -> apps
```

Four things have to be right:

1. `libcamhal-ipu6ep`, **not** `libcamhal-ipu6ep0`. The trailing-zero package is an empty transitional stub; the real plugin only ships in the former. Getting this wrong gives `CamHAL[ERR] failed to open library: .../ipu6ep.so`.
2. An Ubuntu HWE kernel. PSYS was never upstreamed and only exists as prebuilt modules matched to Ubuntu kernel ABIs, so System76's kernel has ISYS but no PSYS and the HAL dies with `Failed to open PSYS`.
3. `RESUME=none`, or the initramfs waits forever on the random-key `cryptswap` and drops to a shell.
4. A WirePlumber rule hiding the 32 raw ISYS nodes, which cannot be opened and make apps fail with `error set output format: -22`.

Do not install `libcamera0.2`, `libcamera-tools`, or `gstreamer1.0-libcamera` for this. Nothing here goes through libcamera, and the PipeWire libcamera plugin actively breaks Cheese.

## Boot and kernel

Boots via rEFInd rather than Pop's default systemd-boot. rEFInd reads `/boot` off the ext4 root directly and auto-detects kernels, so new kernels appear on their own. Each kernel is its **own top-level icon**; F2/Insert shows the cmdline variants from `/boot/refind_linux.conf`, not a kernel list.

`refind-default-hwe.sh` installs as `/etc/kernel/postinst.d/zz-refind-default-hwe` and repoints `default_selection` at the newest kernel that actually has `intel-ipu6-psys`. This matters because System76's kernel version numbers sort **above** the Ubuntu HWE ones, so without it the default drifts back to a kernel where the camera is dead. It always exits 0, so it can never fail a kernel install.

## Shell

`up` is a function, not an alias, so each step can announce itself in light blue. `updown` and `upstart` are aliases that call it.

```bash
up        # apt update, full-upgrade, autoremove, flatpak update + prune, uv self update, dkms status
updown    # up && shutdown
upstart   # up && reboot
```

`full-upgrade` rather than `upgrade`, because plain `upgrade` never installs new packages and silently holds back transitions, including security updates. `dkms status` at the end is a canary: a broken DKMS tree fails to rebuild modules on kernel updates, and this surfaces it. It exits 0 even when printing errors, so it never gates a reboot.
