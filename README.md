# restarting

[![Stack](https://skillicons.dev/icons?i=linux,bash,git,github,vscode,docker,py,rust,ruby,nodejs,latex,postgres,sqlite&perline=13)](https://skillicons.dev)

A short repository designed to help me quickly acclimate when I need to reinstall my Linux distro, which is typically [Pop!_OS](https://system76.com/pop/).

`restart.sh` targets Pop!_OS 24.04 and is portable to any Debian derivative close enough to Ubuntu 24.04 (noble). Everything tied to one specific machine lives in `xps-9315/`, for the Dell XPS 13 Plus 9315 this was written on.

## Usage

```bash
git clone https://github.com/<you>/restarting.git
cd restarting
./restart.sh
```

`restart.sh` runs `xps-9315/setup.sh` at the end, but only when `/sys/class/dmi/id/product_name` reads `XPS 9315`. On anything else it prints a line and stops there, so the whole run is safe on hardware it was not written for. To run the machine half by hand, or on a machine whose DMI string differs, `FORCE=1 xps-9315/setup.sh`.

On the XPS, reboot afterwards and pick GRUB from the firmware boot menu. Its first entry is always a webcam-capable kernel. See [Boot and kernel](#boot-and-kernel) for why that matters.

Neither script is `set -e`, on purpose: the sections are independent, so one dead repo will not abort the whole run. Re-running is safe; the `.bashrc` edits are guarded against duplication.

## Files

| File | Purpose |
|---|---|
| `restart.sh` | The portable setup: packages, toolchains, docker, drives, shell |
| `xps-9315/setup.sh` | The XPS 13 Plus 9315: webcam, audio, recovery partition, bootloader |
| `xps-9315/grub-shortmenu.sh` | GRUB generator emitting short menu titles, PSYS kernel first |
| `xps-9315/grub-default-hwe.sh` | Kernel postinst hook keeping `GRUB_TOP_LEVEL` on a webcam-capable kernel |
| `xps-9315/refind-default-hwe.sh` | Same idea for rEFInd, kept for the fallback boot path |

## Packages

[![Apps](https://skillicons.dev/icons?i=docker,discord,obsidian,postman,ubuntu&perline=5)](https://skillicons.dev)

Grouped by what the software is for, not by which installer puts it there, matching the section order in the scripts. An apt package and a flatpak that do the same job sit together. Everything down to Communication comes from `restart.sh`; Webcam and Boot come from `xps-9315/setup.sh` and only install on that machine.

| Category | Installation method | Apps |
|---|---|---|
| Desktop and system | apt | `gnome-tweaks` `gnome-shell-extension-manager` `gnome-shell-extensions` `sqlite3` `rsync` `locate` `openssh-server` `smartmontools` `tlp` `tlp-rdw` |
| | apt via `repo.protonvpn.com` | `proton-vpn-gnome-desktop` |
| | apt via `ppa:rodsmith/refind` | `refind`. Commented out; installing a second bootloader is a deliberate step rather than something to run unattended |
| Storage and drives | apt | `ntfs-3g` |
| | flatpak | Pika Backup. The repo has to be set up by hand (passphrase, drive), but the exclude list is worth reproducing; it's written out in the comment above the install line in `restart.sh` |
| | config | `/etc/udisks2/mount_options.conf` preferring the `ntfs3` driver over `ntfs-3g` for removable NTFS volumes, plus the `/mnt/media` fstab entry for the Seagate drive. The fstab entry names `ntfs-3g` directly, so the udisks preference only applies to drives mounted on the fly. It also carries `x-gvfs-show`, without which the drive is absent from the file manager sidebar. A drive pulled without unmounting will refuse to mount under `ntfs3`; see the recovery steps in the comment above that block in `restart.sh` |
| Development | apt | `code` `git-all` `gh` `adb` |
| | apt via `download.docker.com` | `docker-ce` `docker-ce-cli` `containerd.io` `docker-buildx-plugin` `docker-compose-plugin` |
| | apt (LaTeX) | `latexmk` `biber` `chktex` `texlive-latex-recommended` `texlive-latex-extra` `texlive-fonts-recommended` `texlive-fonts-extra` `texlive-science` `texlive-pictures` `texlive-extra-utils` |
| | apt (build deps for `ruby-build`) | `autoconf` `bison` `build-essential` `libssl-dev` `libyaml-dev` `libreadline6-dev` `zlib1g-dev` `libncurses5-dev` `libffi-dev` `libgdbm-dev` `libdb-dev` |
| | flatpak | Postman |
| | upstream install scripts | `uv`, `rustup`, `elan`, `nvm` |
| | git clone | `rbenv` + `ruby-build`, then `gem install bundler jekyll` |
| Media | apt | `mpv` `audacity` `qbittorrent` `imagemagick` `ffmpegthumbnailer` |
| | flatpak | Spotify, Foliate |
| | docker compose | Jellyfin, from `~/jellyfin/compose.yaml` |
| Creative and notetaking | flatpak | Krita, Obsidian |
| Games | apt via `repo.steampowered.com` | `steam-launcher`, installed from Valve's release deb by path rather than by the name `steam`. See [Steam](#steam) |
| | apt | `cockatrice` `curseforge` |
| | flatpak | PCSX2, Dolphin |
| Communication | apt | `thunderbird` `zoom` |
| | apt via `updates.signal.org` | `signal-desktop` |
| | flatpak | Discord |
| Webcam | apt via `ppa:oem-solutions-group/intel-ipu6` | `v4l-utils` `cheese` `libcamhal0` `libcamhal-ipu6ep` `libcamhal-ipu6ep-common` `gstreamer1.0-icamera` `v4l2-relayd` |
| | apt | `linux-generic-hwe-24.04` `linux-modules-ipu6-generic-hwe-24.04` |
| Boot | apt | `grub-efi-amd64` `grub-efi-amd64-signed` `os-prober` |
| | git clone | minegrub theme, into `/boot/grub/themes/minegrub` |

Each third-party repo goes in inside the section that needs it, right before the install, followed by its own `apt update`. Docker's is pinned to `noble`, since Pop's codename is its own. Flathub is the one exception, added up top, since a flatpak install shows up as early as the storage section.

`xps-9315/setup.sh` also writes config with no package attached: the `/recovery` fstab entry, the WirePlumber rules hiding the raw IPU6 nodes and the unwanted audio sinks, a udev rule and a `v4l2-relayd` service override, the `rt714` mic boost, and everything in `/etc/default/grub`.

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

The VS Code LaTeX Workshop extension shells out to `latexmk` by default, uses `latexindent` (in `texlive-extra-utils`) for formatting, and `chktex` for linting. `texlive-full` also works but is roughly 6 GB; the set in [Packages](#packages) is the useful subset.

## Storage

`/etc/udisks2/mount_options.conf` sets `ntfs_drivers=ntfs,ntfs3`. That is a preference list, not a fallback chain: udisks takes the first driver it supports and does not retry with the next one if the mount fails. `ntfs` there means ntfs-3g, so putting it first is what makes it the default. It only affects drives mounted on the fly; the `/mnt/media` fstab entry names `ntfs-3g` directly.

The two drivers fail on opposite things. ntfs-3g refuses a volume whose `$MFT` and `$MFTMirr` disagree, but silently clears the dirty flag left by an unclean eject. ntfs3 handles the `$MFTMirr` case but refuses a dirty volume unless mounted with `force`, which udisks does not allow as an ad hoc option.

This list used to lead `ntfs3`, on the argument that a drive pulled without unmounting should fail loudly rather than be quietly papered over. That reasoning was sound and the conclusion was still wrong, because ntfs3 has a second failure mode that is not loud at all: it cannot read NTFS-compressed files, and returns `EINVAL` for them on a plain `stat`.

That surfaces as `ls: cannot access 'First World.zip': Invalid argument` on a scattered handful of files with unremarkable ASCII names, sitting among 47,099 that are fine. It reads as filesystem corruption and it is not. Remounting the same volume with ntfs-3g walks the whole tree with zero errors and reads every one of them. The tell is apparent size against on-disk size, since a compressed file occupies less than it claims:

```bash
stat -c '%s apparent, %b*%B on disk  %n' FILE   # 9511282 apparent, 7716864 on disk
```

Windows compression is per-file and carries no external marker, so there is no warning about which files will vanish. Trading a loud failure on dirty volumes for not having healthy files present themselves as damaged is the better deal, so ntfs-3g leads now. Dirty volumes still need the fix below, they just need it after a mount attempt that says so less clearly.

The file manager reports "wrong fs type, bad option, bad superblock" and the kernel logs `volume is dirty and "force" flag is not set`. To recover:

```bash
sudo ntfsfix -d /dev/sdXN
```

The `-d` is the whole point: it clears the `VOLUME_IS_DIRTY` bit in `$Volume`. Plain `ntfsfix` with no flags **sets** that bit on its way out to schedule a chkdsk, leaving the volume in exactly the state ntfs3 refuses. Mounting with ntfs-3g does not clear it either; its "The disk contains an unclean file system ... Fixing." message is about emptying the `$LogFile` journal, a separate thing.

If ntfs-3g refuses outright with `$MFTMirr does not match $MFT`, run plain `ntfsfix` first to rebuild the mirror, then `ntfsfix -d` to clear the flag it just set. Clearing the flag asserts the volume is healthy, so for anything holding data you care about, run `chkdsk /f` from Windows instead. That is the only real validation; `ntfsfix` only repairs what it names.

### Drives plugged in after boot

An fstab entry does not mount a drive that appears later. systemd's generator makes `mnt-media.mount` `WantedBy=local-fs.target` and nothing else, so the mount is attempted once, at boot. With `nofail` an absent device is not an error, so the unit is skipped and left inactive, and plugging the drive in afterwards creates `dev-sdb2.device` without anything pulling the mount unit in. The drive then sits unmounted for as long as you leave it, with no error in any log, which reads as a broken fstab entry and is not one. `sudo mount /mnt/media` works perfectly the entire time.

`x-systemd.automount` in the entry is the fix. It generates `mnt-media.automount` beside the mount unit; the automount starts at boot whether or not the device is present, and mounts on first access to the path. Adding it to a running system needs the unit started once by hand, after which reboots take care of themselves:

```bash
sudo systemctl daemon-reload
sudo systemctl start mnt-media.automount
```

Restarting udisks2 unmounts everything udisks itself mounted, so expect to redo this and any hand mounts after touching `mount_options.conf`.

### USB-C port speeds

A drive that shows up slow is worth checking against the bus before blaming the drive. The two USB-C ports split across two controllers: SuperSpeed goes to the Thunderbolt controller at `0000:00:0d.0`, which owns buses 1 and 2, while the USB 2 fallback path goes to the PCH xHCI at `0000:00:14.0`, owning buses 3 and 4. So a device that trains SuperSpeed appears on bus 2, and the same device falling back to USB 2 appears on bus 3 alongside the fingerprint reader and Bluetooth. Bus 4 has never had anything on it.

```bash
lsusb -t
for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
    echo "$(basename $d) $(cat $d/speed) $(cat $d/product 2>/dev/null)"
done
```

A USB 3 drive reporting 480 there is not a driver problem, and the way to prove it is that the driver is doing SuperSpeed for something else at the same moment. Check the boot log for link errors too: `device descriptor read`, `error -71`, failed enumeration. Their *absence* is the informative case, because it means the SuperSpeed link never attempted to train rather than trying and failing, which points at the TX/RX pairs not making contact at all.

That was the answer for a SanDisk Ultra Dual Drive Go stuck at 480 Mbps: not the port, since both bus 2 ports had carried SuperSpeed devices that same boot, but the stick's own USB-C plug. It slides out of its housing and collects lint on exactly the outer SuperSpeed pins while the center USB 2 pins keep working. Reseat it, then flip it 180° so the other SuperSpeed pair is selected, then clean it.

Note the device descriptor does not settle whether a drive is USB 2 or USB 3. `version 2.10` is reported both by genuine USB 2.1 devices and by USB 3 devices that have fallen back, because 2.10 signals BOS descriptor support. Only the negotiated speed tells you. Also, manufacturer `USB` with product `SanDisk 3.2Gen1`, leading spaces included, is the normal pattern for recent genuine SanDisk drives, not a counterfeit tell.

### File manager sidebar

A partition listed in `/etc/fstab` is hidden from the sidebar unless its entry says `x-gvfs-show`. This is easy to misread as a permissions or mount problem, because the drive is mounted and readable the whole time. `gio mount -l` tells them apart: a suppressed drive appears as a `Drive` with no `Volume` under it at all, where a drive udisks mounted itself gets a `Volume` and a `Mount` under `/media/$USER`. That is the only reason the backup drive shows up without any config: it has no fstab entry.

So the `/mnt/media` entry carries `x-gvfs-show`, plus `x-gvfs-name=Media` to label it something better than "4.5 TB Volume". This covers Nautilus and COSMIC Files together, since `cosmic-files` links `libgio-2.0` and reads the same GVolumeMonitor. gvfs watches fstab, so the sidebar picks the change up without a remount; the file managers cache it and need a restart.

### Backups

Pika Backup's own config cannot be scripted: it needs the repo passphrase and the target drive picked in the GUI. The exclude list is worth reproducing by hand, in `~/.var/app/org.gnome.World.PikaBackup/config/pika-backup/backup.json`. Keep the four predefined categories (Caches, Trash, FlatpakApps, VmsContainers) plus PathPrefix Videos/Movies, and add:

```json
{"Fnmatch": "*/node_modules"}
{"Fnmatch": "*/__pycache__"}
{"Fnmatch": "home/sam/Documents/projects/*/build"}
{"Fnmatch": "home/sam/Documents/projects/*/dist"}
```

Fnmatch maps to borg's `fm:` patterns, and borg matches against the archive path with no leading slash, which is why these start at `home/sam`. `build` and `dist` are scoped to `Documents/projects` on purpose: both names hold real content often enough elsewhere that a blanket `*/build` would silently drop files. `node_modules` and `__pycache__` are always regenerable, so they stay unscoped.

Do not bother excluding `.venv` or cargo `target/`. uv and cargo both write a `CACHEDIR.TAG`, and the Caches category already passes `--exclude-caches` to borg. On this machine that is 62G of the 77G under `Documents/projects`, excluded before any rule above applies.

## File indexing

GNOME's indexer chokes on `~/Documents/Books & PDFs`, and the failure mode is worse than it sounds. When one file exceeds `tracker-extract-3`'s wall-clock deadline, the watchdog does not skip that file, it kills the whole extractor process: `File '...' took too long to process. Shutting down everything`. `tracker-miner-fs-3` restarts it a second later and redoes the batch, so a library of large textbooks becomes a restart loop that burns a core and records one failure per cycle. Measured here at 32 kills in 20 minutes, each costing about 57 seconds.

The default deadline is 10 seconds, which is almost exactly what a thousand-page PDF costs to extract. That is the whole problem: the same book measured 12.2s and 9.4s on back-to-back runs, so whether a given file fails is jitter, not a property of the file. Files are not corrupt. All 136 that failed here parse clean under `pdfinfo` and extract fine by hand.

The only knob is the `TRACKER_EXTRACT_DEADLINE` environment variable, which is easy to miss because there is nothing in gsettings and nothing in `tracker3`'s options. It goes on `tracker-miner-fs-3.service` rather than on the extractor, because `tracker-extract-3` has no unit of its own: miner-fs spawns it with `--socket-fd 3` and it inherits the environment.

Two dead ends worth not repeating. `Tracker3.Extract max-bytes` caps how much text is *stored*, not how much is *extracted*, so lowering it does not buy any time (measured 10.4-10.7s at 1 MB against 10.7-11.1s at 256 KB). And `tracker3 daemon --pause` stops the crawl but leaves the extract decorator draining its queue, so it does not quiet the loop; stopping the service is the only thing that does.

Raising the deadline to 60s took this library from 133 recorded failures to 4, and the extractor went from dying every 57 seconds to running for hours. The crash loop was not merely slow, it was destroying progress: every kill made miner-fs redo the batch, so the indexed count sat frozen for an hour. Once the kills stopped the whole backlog drained in about five minutes.

Failure records are sticky, so files that failed under the old deadline need clearing before they get another attempt. `tracker3 reset -f <path>` does one. Clear only recorded failures, never the whole index, so files already extracted are never put back at risk.

Except `tracker3 reset -f` cannot clear a path containing an apostrophe. It builds its SPARQL by string interpolation without escaping, so `O'Regan` closes the string literal and the query dies with `Parser error at byte 150, expected one of LANGTAG, '^^', ...`. It exits 1, which is easy to miss inside a loop that only counts successes. Nothing is wrong with those files: a fresh copy with an apostrophe in the name indexes perfectly, so this is a CLI bug and nothing more.

Killing the extractor mid-write also leaves files in a state no retry reaches. `tracker:extractorHash` gets written before the extracted metadata lands, so a file caught by the old watchdog ends up flagged as already processed while holding nothing but filesystem facts: size, dates, name, and no `nie:title`, no `plainTextContent`, no `nfo:PaginatedTextDocument`. It is absent from the failure list, so it looks fine by every counter, and tracker will never revisit it. Three files here were stuck that way.

Getting one unstuck means making tracker forget it, and neither obvious route works. `touch` alone does nothing, because inotify is not delivering changes for `~/Documents` and only a crawl notices; the `touch` that appeared to work only did because a crawl happened to be in flight. A SPARQL `DELETE` does not work either, since the subject is the `file://` IRI itself and putting that IRI in subject position fails with `Could not run query, SQL logic error`. What does work is moving the file out of the indexed tree (`~/.cache` is not indexed), restarting the miner so the crawl records the deletion, moving it back, and restarting again. Verify with checksums on the way out and back.

The useful audit is not the failure count, which showed 4 while 6 files were actually unparsed. Diff the files on disk against what has real extracted metadata:

```bash
tracker3 sparql --dbus-service org.freedesktop.Tracker3.Miner.Files -q '
SELECT DISTINCT ?u WHERE {
  ?ie a nfo:Document ; nie:isStoredAs/nie:url ?u .
  FILTER(STRSTARTS(STR(?u), "file:///home/sam/Documents/Books"))
}'
```

Note this counts `desktop.ini` files as documents too, so the raw totals will not line up with a `find` count; compare the sorted lists, not the numbers.

The last few holdouts are not timeouts at all, and it is worth knowing the two shapes so they are not mistaken for a regression. Three EPUBs fail because `META-INF/container.xml` starts with a UTF-8 BOM, which tracker feeds straight to GMarkup, and GMarkup does not skip a BOM: `Could not get EPUB container.xml file: Error on line 1 char 1: Document must begin with an element`. The files are valid, the XML spec allows a BOM on UTF-8, so this is a tracker bug. Exactly 3 of 245 EPUBs here are affected. Rewriting `container.xml` without the BOM fixes them. The other is a `.docx` carrying a `.doc` extension, so tracker guesses `application/msword` from the name and hands it to an extractor that cannot read OOXML. That one is what `cuarto-oscuro --fix-extensions` is for.

## Docker and Jellyfin

[![Docker](https://skillicons.dev/icons?i=docker,postgres&perline=2)](https://skillicons.dev)

The service is enabled, and `$USER` is added to the `docker` group so it works without `sudo`. That needs a re-login (or `newgrp docker`) to take effect.

Jellyfin runs as a container, not an apt package. `compose.yaml` lives in `~/jellyfin` and is committed separately. It bind-mounts `/mnt/media` read-only and needs `/dev/dri` for hardware transcoding, so the script also creates `/mnt/media` and adds the fstab entry for the Seagate drive. That UUID is specific to the physical disk; re-check with `blkid` if it's ever replaced.

Two fstab options on that entry exist to stop the library from silently coming up empty:

- `x-systemd.device-timeout=30s`, not the more obvious 10s. systemd waits on the `/dev/disk/by-uuid` symlink, which udev only creates after probing the filesystem, well after the block device appears. With two UAS drives behind the VIA hub the udev queue is congested enough at boot that 10s expired while the disk was plugged in the whole time. Combined with `nofail` that failure is silent: boot completes and `/mnt/media` is just empty.
- `x-systemd.before=docker.service`. The container is `restart: unless-stopped`, so docker starts it at boot. A bind mount captures whatever the host has at container start, so if docker wins the race the container holds an empty directory and never picks the filesystem up, staying empty until it is restarted. This is an ordering-only dependency, not `Requires`: if the drive is missing, docker should still come up for everything else.

If Jellyfin ever shows an empty library after a reboot, check `findmnt /mnt/media` before touching anything in Jellyfin itself.

## Steam

Two different packages are named `steam`, and they are not interchangeable:

| Provider | Depends on | Steam root |
|---|---|---|
| Valve, `repo.steampowered.com` | `steam-launcher` | `~/.local/share/Steam` |
| Pop!_OS, `apt.pop-os.org` | `steam-installer` | `~/.steam/debian-installation` |

Pop pins its own at priority 1001 against Valve's 500, so `apt install steam` resolves to Pop's regardless of which repos are enabled. `restart.sh` installs Valve's release deb by path to sidestep the name entirely. Check which one is live with `apt policy steam` and `dpkg -l | grep steam`.

### When Steam disappears from the dock

The symptom is that Steam launches fine from a terminal and `dpkg -l` shows it installed, but it is in neither the dock nor the app grid.

`~/.local/share/applications` outranks `/usr/share/applications` in XDG lookup order, so a user-level entry shadows the system one of the same name. When that user entry is a **broken symlink**, GNOME resolves `steam.desktop` to nothing and drops the app rather than falling through to the working file underneath. Migrating from Pop's package to Valve's leaves exactly that: a link into `~/.steam/debian-installation/deb-installer`, which goes away with the package that owned it. Nothing repairs it on its own, since the package owning the real entry is already installed and has no reason to touch `~/.local`.

Inspecting `/usr/share/applications/steam.desktop` is a red herring; it is fine. Validate the user-level one instead:

```bash
desktop-file-validate ~/.local/share/applications/steam.desktop   # "file does not exist"
```

Then confirm what GNOME itself resolves, which is authoritative because it is the same API the shell uses:

```bash
python3 -c "import gi; gi.require_version('Gio','2.0'); from gi.repository import Gio; a = Gio.DesktopAppInfo.new('steam.desktop'); print(bool(a) and a.should_show())"
```

`restart.sh` prunes dangling entries in that directory after installing Steam. To repair an existing install by hand, delete the dead link, rebuild the cache, and pin it:

```bash
rm ~/.local/share/applications/steam.desktop
update-desktop-database ~/.local/share/applications
gsettings set org.gnome.shell favorite-apps \
    "$(gsettings get org.gnome.shell favorite-apps | sed "s/\]$/, 'steam.desktop']/")"
```

No logout is needed. gnome-shell watches both that directory and dconf, so all three take effect immediately. Run the `gsettings` line only once; it appends unconditionally, and a duplicated favorite shows up as two icons.

`StartupWMClass` is a dead end here, and is what most search results will suggest. Valve deliberately ships no such key: GNOME falls back to matching WM_CLASS against the desktop file basename, and `steam` matches `steam.desktop`. Adding a user-level override to supply it puts a second file into the very directory whose shadowing caused the problem, which masks the cause instead of fixing it.

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
4. The 32 raw ISYS nodes hidden from apps, at both the WirePlumber and the udev level. See [Raw ISYS nodes](#raw-isys-nodes).

Do not install `libcamera0.2`, `libcamera-tools`, or `gstreamer1.0-libcamera` for this. Nothing here goes through libcamera, and the PipeWire libcamera plugin actively breaks Cheese.

### Raw ISYS nodes

`/dev/video1` through `/dev/video32` are the raw IPU6 ISYS capture nodes. The only one meant to be opened is `/dev/video0`, the v4l2loopback device named `Intel MIPI Camera`.

They are not protected out of the box, contrary to what the `libcamhal-common` rule looks like it does. `/usr/lib/udev/rules.d/72-intel-mipi-ipu6-camera.rules` only does `TAG-="uaccess"`, which drops the login ACL and nothing else. The nodes stay `root:video 0660`, so any user in the `video` group can still open all 32. The WirePlumber rule covers PipeWire clients, but Firefox enumerates `/dev/video*` itself and offers every node it can open.

An app that opens a raw node wedges the sensor:

```
CamHAL[ERR] Device node /dev/video17 IOCTL VIDIOC_STREAMON error: Invalid argument
CamHAL[ERR] Camera device starts failed.
CamHAL[WAR] <id0>@waitFrame, time out happens, wait recovery
```

That last line then repeats every five seconds. No frames reach v4l2loopback, so `/dev/video0` keeps serving the last frame it got, and a call shows a **frozen image** even though the preview looked fine before the stream started. Find the culprit by listing who holds the nodes:

```bash
sudo fuser -v /dev/video*
```

`73-hide-ipu6-raw-nodes.rules` sets `GROUP="root", MODE="0660"` on everything matching `ENV{ID_V4L_PRODUCT}=="ipu6"`, which no user app can then open. It is safe because `v4l2-relayd@default` has no `User=` and runs as root, and `/dev/video0` reports `ID_V4L_PRODUCT="Intel MIPI Camera"` so the rule never matches it.

Order matters when applying it by hand: `udevadm trigger` re-creates the nodes along with any ACLs already granted, so `setfacl -b` has to come **after** the trigger, not before. A named-user ACL entry grants access on its own, so a leftover `user:sam:rw-` keeps a node openable no matter what the group is. Check with `getfacl /dev/video5 | grep sam`, and note that `test -r` answers the question without opening the device and risking a wedge.

### When the relay gives up

`v4l2-relayd@default` is `Restart=always` with no `RestartSec`, so a camera that is briefly busy burns systemd's default 5-starts-in-10s limit in about two seconds, and the service then stays dead with `start-limit-hit`. A plain `restart` will not revive it:

```bash
sudo systemctl reset-failed v4l2-relayd@default
sudo systemctl start v4l2-relayd@default
```

The drop-in at `/etc/systemd/system/v4l2-relayd@default.service.d/override.conf` raises that to 10 starts per 60s with `RestartSec=2`, so a transient conflict recovers on its own instead of needing the two commands above.

## Audio

WirePlumber picks the sink with the highest `priority.session` whenever the explicitly chosen one is unavailable. The Blue Yeti's headphone jack comes in at 1109, above the Bose earbuds at 1010 and the laptop speakers at 712, so audio kept landing in a microphone.

`51-hide-unwanted-sinks.conf` disables that node and the three HDMI/DisplayPort sinks, which leaves earbuds and then speakers. Only the Yeti's playback node is touched. Its capture node is separate, is untouched, and still wins as the default source at 2109.

Match on `api.alsa.card.name`, not `alsa.card_name`. `alsa.lua` copies the former into the node properties just before it applies these rules and checks `node.disabled`; the latter is added afterwards, so a rule keyed on it looks correct and silently never fires. Confirm a rule actually fired with `journalctl --user -u wireplumber -b | grep disabled`.

Hiding the HDMI sinks means no audio over HDMI or DisplayPort at all. There is no way around that with a profile: the SOF card offers only `off`, `HiFi`, and `pro-audio`, and `HiFi` bundles all four outputs together.

### Quiet internal microphone

The built-in mic array is far quieter on Linux than on Windows, and turning the input up in Settings barely helps. The reason is that the gain is missing on the hardware side, not the software side. The PipeWire source already sits at 0 dB against a base volume of -30 dB, so there is almost no headroom left there, while the `rt714` codec's two mic boost controls are left at 0:

```bash
amixer -c sofsoundwire cget name='rt714 FU0C Boost'   # 0-3, 10dB a step
amixer -c sofsoundwire cget name='rt714 FU0E Boost'
```

Windows enables these, Linux does not. Setting both to 2 is +20 dB and is audibly louder to people on the other end. Boost ahead of the ADC is preferable to software gain after it, since software gain amplifies the converter's noise along with the signal.

```bash
amixer -c sofsoundwire cset name='rt714 FU0C Boost' 2,2,2,2,2,2,2,2
amixer -c sofsoundwire cset name='rt714 FU0E Boost' 2,2,2,2,2,2,2,2
sudo alsactl store 0
```

Set them by name rather than by numid, which shifts with the topology. Without `alsactl store` the values are gone at the next boot, since `alsa-restore.service` replays `/var/lib/alsa/asound.state`.

The two controls are not additive in series, so both at 2 is not +40 dB. Which one carries the DMIC path is still unestablished. Measuring it needs a **fixed** sound source and a mic nothing else is using: measurements taken during a call are worthless, because the thing being measured is other people talking.

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

- `xps-9315/grub-shortmenu.sh` installs as `/etc/grub.d/09_shortmenu` and emits the PSYS-capable kernel as the **first** entry. With `GRUB_DEFAULT=0` the pin is structural rather than something a sort order can undo. It falls back to the newest kernel overall rather than emitting an empty menu.
- `xps-9315/grub-default-hwe.sh` installs as `/etc/kernel/postinst.d/zz-grub-default-hwe` and maintains `GRUB_TOP_LEVEL` in `/etc/default/grub`. Unused while `09_shortmenu` is active, but it means re-enabling `10_linux` does not silently break the camera. It sorts before `zz-update-grub`, so `grub.cfg` regenerates with the new value in the same kernel install, and it always exits 0 so it can never fail one.

`GRUB_TOP_LEVEL` is the right knob for this rather than `GRUB_DEFAULT=<index>` (indexes shift) or a generated menuentry id (they embed the ABI version and break on the next bump). `10_linux` feeds it to `grub_move_to_front`.

### Short menu titles

`09_shortmenu` also replaces the stock generators, which are `chmod -x`'d:

```
10_linux  10_linux_zfs  20_linux_xen  30_os-prober  30_uefi-firmware  35_fwupd
```

They emit titles like `Windows Boot Manager (on /dev/nvme0n1p1)` and `Advanced options for Pop!_OS GNU/Linux`, which overflow minegrub's 600px button pixmaps at font size 30. That overflow is most of what makes a themed menu look broken. The replacements are `Pop OS`, `Windows`, `Recovery`, `Advanced`, `Firmware Settings`. Dropping `!` and `_` is deliberate too: the Minecraft `.pf2` fonts carry no glyph for either, so `Pop!_OS` renders as `Pop OS` whether you ask for it or not.

`Windows` and `Recovery` are each guarded by a `blkid -U` check and skipped with a message to stderr when their partition is absent, so the generator still produces a working menu on a machine that has neither.

**Adding or removing a top-level entry means editing the theme too.** minegrub positions `static_bar.png` with a hardcoded offset keyed to the number of boot options, so a menu with the wrong count draws the bar over or below where it belongs. The knob is `top = 40%+N` in `/boot/grub/themes/minegrub/theme.txt`, and the file carries a lookup table next to it:

| Boot options | Offset |
| --- | --- |
| 4 | `40%+314` |
| 5 | `40%+386` |
| 6 | `40%+458` |

Five is current: `Pop OS`, `Windows`, `Recovery`, `Advanced`, `Firmware Settings`. It was four until the `Recovery` entry was added. Note this is theme state, not `grub.cfg` state, so it survives `update-grub` and is read fresh at boot; changing it needs no regeneration. Note also that the theme is a `git clone` rather than a file in this repo, so this edit does not travel with a reinstall and has to be redone by hand.

### Recovery partition

`Recovery` boots the Pop recovery image on `nvme0n1p6`, which can reinstall the OS. It is unrelated to the per-kernel `(recovery)` entries inside `Advanced`; those are ordinary single-user boots of the installed system.

Two things about this partition are easy to get wrong, and it shipped wrong on this machine: it was unmounted and unreferenced, holding a 22.04 image on a 24.04 system.

- **It must be mounted at `/recovery`.** `pop-upgrade` finds it by looking for `/recovery` in `/proc/mounts`, so with no mount it reports no recovery partition at all rather than an unmounted one, and `pop-upgrade recovery check` exits 1 printing nothing useful. `xps-9315/setup.sh` adds the fstab entry.
- **GRUB will not generate the boot entry.** `pop-upgrade` writes `/boot/efi/EFI/Recovery-<uuid>/` and registers the entry with **systemd-boot**, which is not what boots this machine. `xps-9315/grub-shortmenu.sh` carries the entry explicitly; its kernel arguments are copied from `boot/grub/grub.cfg` inside the recovery ISO rather than reconstructed.

Refresh the image with `sudo pop-upgrade recovery upgrade from-release <version>`. It downloads roughly 3.4 GB to `/var/cache/pop-upgrade/` and syncs it across, which fits the 4.3 GB partition with about 1 GB to spare.

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
