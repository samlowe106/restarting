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

Then reboot and pick GRUB from the firmware boot menu. Its first entry is always a webcam-capable kernel. See [Boot and kernel](#boot-and-kernel) for why that matters.

`restart.sh` is not `set -e`, on purpose: the sections are independent, so one dead repo will not abort the whole run. Re-running it is safe; the `.bashrc` edits are guarded against duplication.

## Files

| File | Purpose |
|---|---|
| `restart.sh` | The whole setup, top to bottom |
| `grub-shortmenu.sh` | GRUB generator emitting four short menu titles, PSYS kernel first |
| `grub-default-hwe.sh` | Kernel postinst hook keeping `GRUB_TOP_LEVEL` on a webcam-capable kernel |
| `refind-default-hwe.sh` | Same idea for rEFInd, kept for the fallback boot path |

## Packages

[![Apps](https://skillicons.dev/icons?i=docker,discord,obsidian,postman,ubuntu&perline=5)](https://skillicons.dev)

Grouped by what the software is for, not by which installer puts it there, matching the section order in `restart.sh`. An apt package and a flatpak that do the same job sit together.

### Desktop and system

| Installation method | Apps |
|---|---|
| apt | `gnome-tweaks` `gnome-shell-extension-manager` `gnome-shell-extensions` `sqlite3` `rsync` `locate` `openssh-server` `smartmontools` `tlp` `tlp-rdw` |
| apt via `repo.protonvpn.com` | `proton-vpn-gnome-desktop` |
| apt via `ppa:rodsmith/refind` | `refind`. Commented out; installing a second bootloader is a deliberate step rather than something to run unattended |

### Storage and drives

| Installation method | Apps |
|---|---|
| apt | `ntfs-3g` |
| flatpak | Pika Backup |
| config | `/etc/udisks2/mount_options.conf` preferring the `ntfs3` driver, plus the `/mnt/media` fstab entry for the Seagate drive |

### Development

| Installation method | Apps |
|---|---|
| apt | `code` `git-all` `gh` `adb` |
| apt via `download.docker.com` | `docker-ce` `docker-ce-cli` `containerd.io` `docker-buildx-plugin` `docker-compose-plugin` |
| apt (LaTeX) | `latexmk` `biber` `chktex` `texlive-latex-recommended` `texlive-latex-extra` `texlive-fonts-recommended` `texlive-fonts-extra` `texlive-science` `texlive-pictures` `texlive-extra-utils` |
| apt (build deps for `ruby-build`) | `autoconf` `bison` `build-essential` `libssl-dev` `libyaml-dev` `libreadline6-dev` `zlib1g-dev` `libncurses5-dev` `libffi-dev` `libgdbm-dev` `libdb-dev` |
| flatpak | Postman |
| upstream install scripts | `uv`, `rustup`, `elan`, `nvm` |
| git clone | `rbenv` + `ruby-build`, then `gem install bundler jekyll` |

### Media

| Installation method | Apps |
|---|---|
| apt | `mpv` `audacity` `qbittorrent` `imagemagick` `ffmpegthumbnailer` |
| flatpak | Spotify, Foliate |
| docker compose | Jellyfin, from `~/jellyfin/compose.yaml` |

### Creative and notetaking

| Installation method | Apps |
|---|---|
| flatpak | Krita, Obsidian |

### Games

| Installation method | Apps |
|---|---|
| apt | `steam` `cockatrice` `curseforge` |
| flatpak | PCSX2, Dolphin |

### Communication

| Installation method | Apps |
|---|---|
| apt | `thunderbird` `zoom` |
| apt via `updates.signal.org` | `signal-desktop` |
| flatpak | Discord |

### Webcam

| Installation method | Apps |
|---|---|
| apt via `ppa:oem-solutions-group/intel-ipu6` | `v4l-utils` `cheese` `libcamhal0` `libcamhal-ipu6ep` `libcamhal-ipu6ep-common` `gstreamer1.0-icamera` `v4l2-relayd` |
| apt | `linux-generic-hwe-24.04` `linux-modules-ipu6-generic-hwe-24.04` |

### Boot

| Installation method | Apps |
|---|---|
| apt | `grub-efi-amd64` `grub-efi-amd64-signed` `os-prober` |
| git clone | minegrub theme, into `/boot/grub/themes/minegrub` |

Each third-party repo goes in inside the section that needs it, right before the install, followed by its own `apt update`. Docker's is pinned to `noble`, since Pop's codename is its own. Flathub is the one exception, added up top, since a flatpak install shows up as early as the storage section.

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

The VS Code LaTeX Workshop extension shells out to `latexmk` by default, uses `latexindent` (in `texlive-extra-utils`) for formatting, and `chktex` for linting. `texlive-full` also works but is roughly 6 GB; the set under [Development](#development) is the useful subset.

## Docker and Jellyfin

[![Docker](https://skillicons.dev/icons?i=docker,postgres&perline=2)](https://skillicons.dev)

The service is enabled, and `$USER` is added to the `docker` group so it works without `sudo`. That needs a re-login (or `newgrp docker`) to take effect.

Jellyfin runs as a container, not an apt package. `compose.yaml` lives in `~/jellyfin` and is committed separately. It bind-mounts `/mnt/media` read-only and needs `/dev/dri` for hardware transcoding, so the script also creates `/mnt/media` and adds the fstab entry for the Seagate drive. That UUID is specific to the physical disk; re-check with `blkid` if it's ever replaced.

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

Boots via GRUB with the [minegrub](https://github.com/Lxtharia/minegrub-theme) theme, rather than Pop's default systemd-boot. Three fallbacks stay installed and reachable from the firmware boot menu, so a bad config is never more than an `efibootmgr` reorder from being undone:

| Boot path | Status |
|---|---|
| GRUB | Default. ESP directory `\EFI\GRUB`, but the firmware label reads `Pop!_OS`, since `grub-install` takes it from `GRUB_DISTRIBUTOR` |
| rEFInd | Fallback, installed on both ESPs |
| systemd-boot | Fallback, kept current by Pop's own `kernelstub` hook |

`grub-pc`, the legacy BIOS build, gets pulled in as a `linux-image` Recommends even on a UEFI machine. It conflicts with `grub-efi-amd64`, so apt removes it during the install. (That's expected.)

### Pinning the kernel

The webcam only works on a kernel that has `intel-ipu6-psys`, and System76's kernel version numbers sort **above** the Ubuntu HWE ones, so anything that picks "newest" picks wrong. Two mechanisms, belt and braces:

- `grub-shortmenu.sh` installs as `/etc/grub.d/09_shortmenu` and emits the PSYS-capable kernel as the **first** entry. With `GRUB_DEFAULT=0` the pin is structural rather than something a sort order can undo. It falls back to the newest kernel overall rather than emitting an empty menu.
- `grub-default-hwe.sh` installs as `/etc/kernel/postinst.d/zz-grub-default-hwe` and maintains `GRUB_TOP_LEVEL` in `/etc/default/grub`. Unused while `09_shortmenu` is active, but it means re-enabling `10_linux` does not silently break the camera. It sorts before `zz-update-grub`, so `grub.cfg` regenerates with the new value in the same kernel install, and it always exits 0 so it can never fail one.

`GRUB_TOP_LEVEL` is the right knob for this rather than `GRUB_DEFAULT=<index>` (indexes shift) or a generated menuentry id (they embed the ABI version and break on the next bump). `10_linux` feeds it to `grub_move_to_front`.

### Short menu titles

`09_shortmenu` also replaces the stock generators, which are `chmod -x`'d:

```
10_linux  10_linux_zfs  20_linux_xen  30_os-prober  30_uefi-firmware  35_fwupd
```

They emit titles like `Windows Boot Manager (on /dev/nvme0n1p1)` and `Advanced options for Pop!_OS GNU/Linux`, which overflow minegrub's 600px button pixmaps at font size 30. That overflow is most of what makes a themed menu look broken. The replacements are `Pop OS`, `Windows`, `Advanced`, `Firmware Settings`. Dropping `!` and `_` is deliberate too: the Minecraft `.pf2` fonts carry no glyph for either, so `Pop!_OS` renders as `Pop OS` whether you ask for it or not.

To revert: `chmod -x /etc/grub.d/09_shortmenu`, `chmod +x` the six above, `update-grub`.

The Windows entry chainloads a hardcoded ESP UUID. Re-check it with `lsblk -f` if Windows is ever reinstalled; the entry is skipped silently if that filesystem is not found.

## Shell

`up` is a function, not an alias, so each step can announce itself in light blue. `updown` and `upstart` are aliases that call it.

```bash
up        # apt update, full-upgrade, autoremove, flatpak update + prune, uv self update, dkms status
updown    # up && shutdown
upstart   # up && reboot
```

`full-upgrade` rather than `upgrade`, because plain `upgrade` never installs new packages and silently holds back transitions, including security updates. `dkms status` at the end is a canary: a broken DKMS tree fails to rebuild modules on kernel updates, and this surfaces it. It exits 0 even when printing errors, so it never gates a reboot.
