#!/bin/bash
# Post-install setup for Pop!_OS 24.04 on a Dell XPS 13 Plus 9315.
# Not set -e on purpose: the sections are independent, and one failing
# repo should not abort the rest of the install.
#
# Sections are grouped by what the software is for, not by which installer
# puts it there, so an apt package and a flatpak that do the same job sit
# together. Third-party repos live in the section that needs them, right
# before the install, each followed by its own `apt update`.
set -uo pipefail

DOWNLOADS="$(mktemp -d)"
trap 'rm -rf "$DOWNLOADS"' EXIT

# This repo, so the helper scripts can be found regardless of where it is run from
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Append a block to ~/.bashrc only if a marker string is not already present,
# so re-running this script does not duplicate anything.
bashrc_once() {
    local marker="$1"
    if ! grep -qF "$marker" ~/.bashrc; then
        cat >> ~/.bashrc
    else
        cat > /dev/null
    fi
}

# ---------------------------------------------------------------------------
# base
# Only what every section below depends on: a current system and the flathub
# remote. Each section adds its own repo right before it installs from it
# ---------------------------------------------------------------------------

sudo apt update && sudo apt full-upgrade -y

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ---------------------------------------------------------------------------
# desktop & system
# ---------------------------------------------------------------------------

# gnome tweaks / shell extensions
sudo apt install -y gnome-tweaks gnome-shell-extension-manager gnome-shell-extensions

# cli + system utilities, power management, remote access
sudo apt install -y sqlite3 rsync locate openssh-server smartmontools \
    tlp tlp-rdw

# proton vpn. The release deb only drops in the repo; the client itself comes
# from that repo, so it needs an update in between
wget -P "$DOWNLOADS" https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb
sudo dpkg -i "$DOWNLOADS/protonvpn-stable-release_1.0.8_all.deb"
sudo apt update
sudo apt install -y proton-vpn-gnome-desktop

# refind. Superseded by the GRUB section at the bottom, but kept here because
# it is a useful fallback: leaving rEFInd installed alongside GRUB means a bad
# GRUB config is one efibootmgr reorder away from being recoverable
# sudo add-apt-repository -y ppa:rodsmith/refind
#sudo apt install -y refind

# ---------------------------------------------------------------------------
# storage & drives
# ---------------------------------------------------------------------------

sudo apt install -y ntfs-3g

# This is a preference list, not a fallback chain: udisks uses the first driver
# it supports and does not retry with the next one if the mount fails. "ntfs"
# means ntfs-3g, so ntfs3 has to come first to actually be preferred.
#
# The two drivers fail on opposite things. ntfs-3g refuses a volume whose $MFT
# and $MFTMirr disagree, but silently clears the dirty flag left by an unclean
# eject. ntfs3 is the reverse: it handles the $MFTMirr case, but refuses a dirty
# volume unless mounted with "force", which udisks does not allow as an ad hoc
# option. Preferring ntfs3 is the deliberate choice, since a drive pulled
# without unmounting then fails loudly instead of being quietly papered over.
#
# When that happens the file manager reports "wrong fs type, bad option, bad
# superblock" and the kernel logs 'volume is dirty and "force" flag is not set'.
# To recover:
#     sudo ntfsfix -d /dev/sdXN
# The -d is the whole point: it clears the VOLUME_IS_DIRTY bit in $Volume. Plain
# `ntfsfix` with no flags SETS that bit on its way out to schedule a chkdsk, so
# it leaves the volume in exactly the state ntfs3 refuses to mount.
#
# Mounting with ntfs-3g does not clear the bit either. ntfs-3g prints "The disk
# contains an unclean file system ... Fixing." and mounts anyway, but that
# message is about emptying the $LogFile journal, which is a separate thing. It
# ignores VOLUME_IS_DIRTY rather than clearing it.
#
# If ntfs-3g refuses outright with "$MFTMirr does not match $MFT", run plain
# `sudo ntfsfix /dev/sdXN` first to rebuild the mirror, then `ntfsfix -d` to
# clear the flag it just set. Clearing the flag asserts the volume is healthy,
# so for anything holding data you care about, run `chkdsk /f` from Windows
# instead. That is the only real validation; ntfsfix only repairs what it names.
sudo mkdir -p /etc/udisks2
sudo tee /etc/udisks2/mount_options.conf > /dev/null <<'EOF'
[defaults]
ntfs_drivers=ntfs3,ntfs
EOF

sudo systemctl restart udisks2

# Seagate Portable Drive, the Jellyfin media library. UUID is specific to that
# physical disk, so re-check with `blkid` if the drive is ever replaced.
#
# The device timeout is 30s rather than the more obvious 10s. systemd waits on
# the /dev/disk/by-uuid symlink, which udev only creates after probing the
# filesystem, and that probe lands well after the block device itself. With two
# UAS drives behind the VIA hub the udev queue is congested enough at boot that
# 10s expired while the disk was plugged in the whole time. Combined with
# nofail, that failure is silent: boot completes and /mnt/media is just empty,
# so the first symptom is Jellyfin showing an empty library.
#
# x-systemd.before=docker.service is what keeps that from happening quietly.
# The Jellyfin container is restart: unless-stopped, so docker starts it at
# boot, and it bind-mounts /mnt/media. A bind mount captures whatever the host
# has at container start, so if docker wins the race the container holds an
# empty directory and does not pick the filesystem up when the mount lands
# later. It stays empty until the container is restarted. Ordering the mount
# before docker.service closes that window. Deliberately an ordering-only
# dependency, not Requires: if the drive is missing, docker should still come
# up for everything else.
sudo mkdir -p /mnt/media
if ! grep -q '/mnt/media' /etc/fstab; then
    echo 'UUID=620C6DA000E97169  /mnt/media  ntfs-3g  uid=1000,gid=1000,umask=022,nofail,x-systemd.device-timeout=30s,x-systemd.before=docker.service  0  0' | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
    sudo mount -a
fi

# Pop recovery partition (nvme0n1p6). This mount is not optional plumbing: it is
# how the partition gets used at all. pop-upgrade locates it by looking for
# /recovery in /proc/mounts and then running findmnt for the uuid, so with no
# mount it reports no recovery partition rather than an unmounted one, and
# `pop-upgrade recovery check` just exits 1 with no explanation. The partition
# shipped with this machine unmounted and unreferenced, holding a stale 22.04
# image on a 24.04 system, which is exactly what that silence hides.
#
# Once mounted, refresh the image with:
#     sudo pop-upgrade recovery upgrade from-release 24.04
# and see grub-shortmenu.sh for the boot entry, which GRUB will not generate on
# its own. pop-upgrade only registers the entry with systemd-boot.
sudo mkdir -p /recovery
if ! grep -q '/recovery' /etc/fstab; then
    echo 'UUID=7C59-13DD  /recovery  vfat  defaults,nofail  0  0' | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
    sudo mount -a
fi

# backups
sudo flatpak install -y flathub org.gnome.World.PikaBackup

# The backup config itself cannot be scripted: it needs the repo passphrase and
# the target drive picked in the GUI. What is worth reproducing by hand is the
# exclude list, which lives in
# ~/.var/app/org.gnome.World.PikaBackup/config/pika-backup/backup.json.
#
# Keep the four predefined categories (Caches, Trash, FlatpakApps,
# VmsContainers) plus PathPrefix Videos/Movies, and add these:
#
#     {"Fnmatch": "*/node_modules"}
#     {"Fnmatch": "*/__pycache__"}
#     {"Fnmatch": "home/sam/Documents/projects/*/build"}
#     {"Fnmatch": "home/sam/Documents/projects/*/dist"}
#
# Fnmatch maps to borg's fm: patterns, and borg matches against the archive
# path with no leading slash, which is why these start at "home/sam" rather
# than "/home/sam". build and dist are scoped to Documents/projects on purpose:
# those two names hold real content often enough elsewhere that a blanket
# */build would silently drop files from the backup. node_modules and
# __pycache__ are always regenerable, so those stay unscoped.
#
# Do NOT bother excluding .venv or cargo target/ directories. uv and cargo both
# write a CACHEDIR.TAG, and the Caches category already passes --exclude-caches
# to borg, which skips them. On this machine that is 62G of the 77G under
# Documents/projects, already excluded before any of the rules above apply.

# ---------------------------------------------------------------------------
# development
# ---------------------------------------------------------------------------

# editor, version control, android debugging
sudo apt install -y code git-all gh adb

# api client
sudo flatpak install -y flathub com.getpostman.Postman

# docker
# Jellyfin runs as a container out of ~/jellyfin/compose.yaml, as do most of
# the project repos under ~/Documents/projects
# Repo lives here rather than up top, so it needs its own `apt update`.
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
# Pop!_OS is Ubuntu-based but VERSION_CODENAME is its own, so pin to noble.
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
# So docker works without sudo. Needs a re-login (or `newgrp docker`) to apply
sudo usermod -aG docker "$USER"

# latex
# The VS Code LaTeX Workshop extension shells out to latexmk by default, and
# uses latexindent for formatting and chktex for linting. texlive-full would
# also work but is ~6 GB; this is the useful subset
sudo apt install -y latexmk biber chktex \
    texlive-latex-recommended texlive-latex-extra \
    texlive-fonts-recommended texlive-fonts-extra \
    texlive-science texlive-pictures texlive-extra-utils

# --- toolchains ---
# These are all per-user installs under $HOME, not apt, and each needs a
# ~/.bashrc hook. Without them nothing here is on PATH in a new shell

# uv (python)
curl -LsSf https://astral.sh/uv/install.sh | sh

# rustup (rust)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# elan (lean)
curl -sSf https://elan.lean-lang.org/elan-init.sh | sh -s -- -y

# nvm (node)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts

# rbenv (ruby). Provides the `gem` and `bundle` shims; the apt ruby is shadowed

# ruby-build needs these to compile a Ruby; jekyll comes from `gem` under
# rbenv rather than apt, so that the rbenv shims are what actually runs
sudo apt install -y autoconf bison build-essential libssl-dev libyaml-dev \
    libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev libdb-dev

if [ ! -d "$HOME/.rbenv" ]; then
    git clone https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
    git clone https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build"
fi
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
rbenv install -s "$(rbenv install -l 2>/dev/null | grep -vE '[a-z]' | tail -1)"
rbenv global "$(rbenv versions --bare | tail -1)"
gem install bundler jekyll

bashrc_once 'rbenv init' <<'EOF'

# rbenv - use rbenv-managed Ruby ahead of the system /usr/bin/ruby
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
EOF

# ---------------------------------------------------------------------------
# media
# ---------------------------------------------------------------------------

# players, editing, torrents, thumbnails
sudo apt install -y mpv audacity qbittorrent imagemagick ffmpegthumbnailer

# music and ebooks
sudo flatpak install -y flathub \
    com.spotify.Client com.github.johnfactotum.Foliate

# ---------------------------------------------------------------------------
# jellyfin
# Runs as a container, not an apt package. compose.yaml lives in ~/jellyfin
# and is committed separately; it bind-mounts /mnt/media read-only and needs
# /dev/dri for hardware transcoding.
# ---------------------------------------------------------------------------

if [ -f "$HOME/jellyfin/compose.yaml" ]; then
    ( cd "$HOME/jellyfin" && sudo docker compose up -d )
else
    echo "jellyfin: ~/jellyfin/compose.yaml not found, skipping (restore it from backup)"
fi

# ---------------------------------------------------------------------------
# creative & notetaking
# ---------------------------------------------------------------------------

sudo flatpak install -y flathub org.kde.krita md.obsidian.Obsidian

# ---------------------------------------------------------------------------
# games
#
# `apt install steam` is ambiguous here: two different packages are named steam,
# Valve's (Depends: steam-launcher) and Pop's (Depends: steam-installer). Pop
# pins its own at priority 1001 against Valve's 500, so the bare name always
# resolves to Pop's regardless of which repos are enabled. They disagree about
# where the Steam root lives, ~/.local/share/Steam vs ~/.steam/debian-installation,
# which is what makes switching between them leave debris. Take Valve's.
#
# Unlike the ProtonVPN deb above, this one is the client and not just a repo
# dropper, so it installs in one step; it adds repo.steampowered.com and the
# signing key on the way in, which is what keeps it updated afterwards.
# ---------------------------------------------------------------------------

wget -P "$DOWNLOADS" https://repo.steampowered.com/steam/archive/stable/steam.deb
sudo apt install -y "$DOWNLOADS/steam.deb"

sudo apt install -y cockatrice curseforge

# A user-level .desktop file shadows the system one of the same name, so a
# broken one hides a working app rather than being ignored: GNOME resolves the
# entry to nothing and the app silently vanishes from the dock and app grid,
# with the launcher still on disk and the package still installed.
#
# Going from Pop's steam to Valve's leaves exactly that, a link into
# ~/.steam/debian-installation, which is Pop's Steam root and is gone once its
# package is. Nothing repairs it, since the package that owns the real entry is
# already installed and has no reason to touch ~/.local. Prune the dead ones.
prune_dangling_desktop_entries() {
    local dir="$HOME/.local/share/applications" entry
    [ -d "$dir" ] || return 0
    for entry in "$dir"/*.desktop; do
        if [ -L "$entry" ] && [ ! -e "$entry" ]; then
            echo "pruning dangling desktop entry: ${entry##*/} -> $(readlink "$entry")"
            rm -f "$entry"
        fi
    done
    update-desktop-database "$dir" 2>/dev/null
}

prune_dangling_desktop_entries

# emulation
sudo flatpak install -y flathub \
    net.pcsx2.PCSX2 org.DolphinEmu.dolphin-emu

# ---------------------------------------------------------------------------
# communication
# ---------------------------------------------------------------------------

# mail
sudo apt install -y thunderbird

# zoom
sudo apt install -y zoom

# messaging
# Signal ships its own repo, so that goes in right before the install
wget -O- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor | sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null
wget -O- https://updates.signal.org/static/desktop/apt/signal-desktop.sources | sudo tee /etc/apt/sources.list.d/signal-desktop.sources > /dev/null
sudo apt update
sudo apt install -y signal-desktop

sudo flatpak install -y flathub com.discordapp.Discord

# ---------------------------------------------------------------------------
# shell: update aliases (up, updown, upstart)
# ---------------------------------------------------------------------------

bashrc_once '_up_step()' <<'EOF'

# update aliases
# Light blue headers, but only when stdout is a terminal, so piping `up`
# into a file or a pager does not litter it with escape codes.
_up_step() {
    if [ -t 1 ]; then
        printf '\n\033[1;38;5;117m==> %s\033[0m\n' "$1"
    else
        printf '\n==> %s\n' "$1"
    fi
}

up() {
    _up_step "apt update"                  ; sudo apt update            || return 1
    _up_step "apt full-upgrade"            ; sudo apt full-upgrade -y   || return 1
    _up_step "apt autoremove"              ; sudo apt autoremove -y
    _up_step "flatpak update"              ; flatpak update -y
    _up_step "flatpak uninstall --unused"  ; flatpak uninstall --unused -y
    _up_step "uv self update"              ; uv self update
    _up_step "dkms status"                 ; dkms status
    printf '\n\033[1;32m==> up: done\033[0m\n'
}

alias updown='up && sudo shutdown'
alias upstart='up && sudo reboot'
EOF

# ---------------------------------------------------------------------------
# camera stuff for Dell XPS 9315 (Intel IPU6 / ov01a10)
#
# This is a MIPI sensor, not USB. It runs through Intel's HAL, not libcamera:
#   ov01a10 -> intel_ipu6_isys + intel_ipu6_psys (kernel)
#           -> libcamhal / icamerasrc -> v4l2-relayd -> v4l2loopback
#           -> /dev/video0 -> apps
#
# Do NOT install libcamera0.2 / libcamera-tools / gstreamer1.0-libcamera for
# this. Nothing here goes through libcamera, and the PipeWire libcamera plugin
# actively breaks Cheese by offering devices that can't be opened
# ---------------------------------------------------------------------------

sudo add-apt-repository -y ppa:oem-solutions-group/intel-ipu6

# libcamhal-ipu6ep, NOT libcamhal-ipu6ep0. The trailing-zero package is an
# empty transitional stub; the real plugin (/usr/lib/libcamhal/plugins/ipu6ep.so)
# only ships in libcamhal-ipu6ep. Installing the wrong one gives:
#   CamHAL[ERR] failed to open library: .../ipu6ep.so
sudo apt install -y v4l-utils cheese \
    libcamhal0 libcamhal-ipu6ep libcamhal-ipu6ep-common \
    gstreamer1.0-icamera v4l2-relayd

# PSYS (the IPU6 ISP) was never upstreamed and only exists as prebuilt modules
# matched to Ubuntu kernel ABIs. System76's kernel ships ISYS but no PSYS, so
# the HAL dies with "Failed to open PSYS". Boot the Ubuntu HWE kernel instead.
# Use the META packages so the kernel and its ipu6 modules always upgrade
# together; pinning exact versions is what strands the modules on an upgrade
sudo apt install -y linux-generic-hwe-24.04 linux-modules-ipu6-generic-hwe-24.04

# initramfs-tools otherwise auto-detects the random-key cryptswap as a
# hibernation resume target and hangs at boot, dropping to an initramfs shell.
# A /dev/urandom-keyed swap can never be resumed from anyway
echo 'RESUME=none' | sudo tee /etc/initramfs-tools/conf.d/resume
sudo update-initramfs -u -k all

# The 32 raw IPU6 ISYS nodes (/dev/video1-32) get enumerated by PipeWire, and
# apps that pick one fail with "error set output format: -22". Hide them so
# only the working v4l2loopback device ("Intel MIPI Camera") is offered
mkdir -p ~/.config/wireplumber/wireplumber.conf.d
cat > ~/.config/wireplumber/wireplumber.conf.d/50-hide-ipu6-raw.conf <<'EOF'
monitor.v4l2.rules = [
  {
    matches = [
      {
        device.product.name = "ipu6"
      }
    ]
    actions = {
      update-props = {
        device.disabled = true
      }
    }
  }
]
EOF

# That WirePlumber rule only covers PipeWire clients. Firefox enumerates
# /dev/video* directly and lists every node it can open, and the raw nodes ARE
# openable: libcamhal-common's rule only strips the uaccess ACL, which does
# nothing while $USER is in the video group and the nodes are root:video 0660.
# An app that opens one wedges ISYS, the HAL's STREAMON then fails, and
# v4l2loopback keeps serving its last frame, so calls freeze on a still image.
# Lock them to root: v4l2-relayd runs as root so the HAL still works, and
# /dev/video0 is ID_V4L_PRODUCT="Intel MIPI Camera" so it is never matched
sudo tee /etc/udev/rules.d/73-hide-ipu6-raw-nodes.rules >/dev/null <<'EOF'
SUBSYSTEM=="video4linux", ENV{ID_V4L_PRODUCT}=="ipu6", GROUP="root", MODE="0660", TAG-="uaccess"
EOF
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=video4linux
# after the trigger, not before: the trigger re-creates the nodes and with them
# any stale per-user ACLs that were already granted
sudo setfacl -b /dev/video{1..32} 2>/dev/null

# v4l2-relayd is Restart=always with no RestartSec, so a camera that is briefly
# busy burns systemd's default 5-starts-in-10s limit in about two seconds and
# the service stays dead with start-limit-hit. Recovering from that needs
# "systemctl reset-failed v4l2-relayd@default" first; a plain restart will not
sudo mkdir -p /etc/systemd/system/v4l2-relayd@default.service.d
sudo tee /etc/systemd/system/v4l2-relayd@default.service.d/override.conf >/dev/null <<'EOF'
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
RestartSec=2
EOF
sudo systemctl daemon-reload

# WirePlumber defaults to the sink with the highest priority.session. The Blue
# Yeti's headphone jack comes in at 1109, above the Bose earbuds (1010) and the
# laptop speakers (712), so audio kept landing in a microphone. Disable that
# node and the three HDMI/DisplayPort sinks, leaving earbuds then speakers.
# Only the Yeti's playback node is touched; its capture node still wins as the
# default source at 2109.
#
# Match on api.alsa.card.name, not alsa.card_name: alsa.lua copies the former in
# before it applies these rules, and the latter is added afterwards, so a rule
# keyed on it looks right and silently never fires.
#
# The HDMI node names embed this laptop's PCI path, which is stable for the
# 9315. Re-check with `wpctl status` on different hardware.
cat > ~/.config/wireplumber/wireplumber.conf.d/51-hide-unwanted-sinks.conf <<'EOF'
monitor.alsa.rules = [
  {
    matches = [
      {
        api.alsa.card.name = "Blue Microphones"
        api.alsa.pcm.stream = "playback"
      }
    ]
    actions = {
      update-props = {
        node.disabled = true
      }
    }
  }
  {
    matches = [
      {
        node.name = "alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__HDMI1__sink"
      }
      {
        node.name = "alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__HDMI2__sink"
      }
      {
        node.name = "alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__HDMI3__sink"
      }
    ]
    actions = {
      update-props = {
        node.disabled = true
      }
    }
  }
]
EOF
systemctl --user restart wireplumber

# The internal mic array is very quiet compared to Windows, which enables the
# rt714 codec's mic boost while Linux leaves it at 0. Both controls are 0-3 at
# 10dB a step, so there is up to 30dB per control sitting unused. Boost ahead of
# the ADC beats software gain after it: the PipeWire source is already at 0dB
# with a -30dB base volume, so there is nearly no headroom left on that side.
# Set by name, not numid: numids shift with the topology
amixer -c sofsoundwire cset name='rt714 FU0C Boost' 2,2,2,2,2,2,2,2
amixer -c sofsoundwire cset name='rt714 FU0E Boost' 2,2,2,2,2,2,2,2

# ALSA levels reset on reboot unless they are in /var/lib/alsa/asound.state,
# which alsa-restore.service reloads at boot
sudo alsactl store 0

# If rEFInd is still installed, keep its default on a kernel that has PSYS.
# No-ops when refind.conf is absent, so it is safe to run either way.
if [ -f "$HERE/refind-default-hwe.sh" ]; then
    sudo install -m 0755 "$HERE/refind-default-hwe.sh" /etc/kernel/postinst.d/zz-refind-default-hwe
    sudo /etc/kernel/postinst.d/zz-refind-default-hwe
fi

# ---------------------------------------------------------------------------
# bootloader: GRUB with the minegrub theme
#
# Pop ships systemd-boot and recommends against GRUB, so this is a deliberate
# swap. Two things to know:
#
#   - grub-pc (the legacy BIOS build) gets pulled in as a linux-image
#     Recommends even on a UEFI machine. It is useless here and conflicts with
#     grub-efi-amd64, so apt removes it as part of the install
#   - a distro upgrade may re-assert systemd-boot in the boot order, and Pop's
#     recovery partition does not appear in the GRUB menu
#
# This does NOT reorder the firmware boot entries. Boot GRUB by hand from the
# firmware menu first, confirm it works, then run the efibootmgr line printed
# at the end. rEFInd and systemd-boot both stay installed as fallbacks.
# ---------------------------------------------------------------------------

sudo apt install -y grub-efi-amd64 grub-efi-amd64-signed os-prober
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck

# Set a key in /etc/default/grub, replacing any existing definition
grub_set() {
    local key="$1" val="$2"
    sudo sed -i "/^[[:space:]]*#\?[[:space:]]*${key}=/d" /etc/default/grub
    echo "${key}=${val}" | sudo tee -a /etc/default/grub > /dev/null
}

sudo cp -a /etc/default/grub /etc/default/grub.orig
grub_set GRUB_DEFAULT 0
grub_set GRUB_TIMEOUT_STYLE menu
grub_set GRUB_TIMEOUT 5
# Native panel resolution. Set to `auto` if the menu comes up garbled or 640x480
grub_set GRUB_GFXMODE 1920x1200
grub_set GRUB_GFXPAYLOAD_LINUX keep
grub_set GRUB_DISABLE_OS_PROBER false
grub_set GRUB_CMDLINE_LINUX_DEFAULT '"quiet loglevel=0 systemd.show_status=false splash"'
grub_set GRUB_THEME /boot/grub/themes/minegrub/theme.txt

# minegrub. Skip their install_theme.sh: it also wires up a systemd service
# that rewrites the splash screen from fastfetch output on every boot, which is
# more moving parts than is wanted between the user and a bootloader
git clone --depth 1 https://github.com/Lxtharia/minegrub-theme.git "$DOWNLOADS/minegrub"
sudo rm -rf /boot/grub/themes/minegrub
sudo mkdir -p /boot/grub/themes
sudo cp -r "$DOWNLOADS/minegrub/minegrub" /boot/grub/themes/

# minegrub places its bottom bar image at a hardcoded offset keyed to how many
# top-level boot options there are, and ships tuned for four. 09_shortmenu emits
# five (Pop OS, Windows, Recovery, Advanced, Firmware Settings), so the bar
# lands a slot too high unless this is corrected. The theme file carries the
# whole table next to the value: 4 options is 314, 5 is 386, 6 is 458, each step
# being one 72px row.
#
# This is theme state rather than grub.cfg state, so it is read fresh at boot
# and needs no update-grub. If a boot option is ever added or removed, this
# number has to move with it or the menu quietly looks broken.
sudo sed -i 's|^\ttop = 40%+314$|\ttop = 40%+386|' /boot/grub/themes/minegrub/theme.txt
grep -q 'top = 40%+386' /boot/grub/themes/minegrub/theme.txt \
    || echo "minegrub: bottom bar offset not applied, check theme.txt" >&2

# Short menu titles. The stock generators emit things like "Windows Boot
# Manager (on /dev/nvme0n1p1)", which overflows minegrub's 600px buttons at
# font size 30. 09_shortmenu replaces them with four short entries, and always
# puts the PSYS-capable kernel first so GRUB_DEFAULT=0 pins the camera kernel
if [ -f "$HERE/grub-shortmenu.sh" ]; then
    sudo install -m 0755 "$HERE/grub-shortmenu.sh" /etc/grub.d/09_shortmenu
    for gen in 10_linux 10_linux_zfs 20_linux_xen 30_os-prober 30_uefi-firmware 35_fwupd; do
        [ -f "/etc/grub.d/$gen" ] && sudo chmod -x "/etc/grub.d/$gen"
    done
fi

# Belt and braces: if 09_shortmenu is ever disabled and 10_linux re-enabled,
# GRUB_TOP_LEVEL keeps the PSYS kernel as entry 0 anyway
if [ -f "$HERE/grub-default-hwe.sh" ]; then
    sudo install -m 0755 "$HERE/grub-default-hwe.sh" /etc/kernel/postinst.d/zz-grub-default-hwe
    sudo /etc/kernel/postinst.d/zz-grub-default-hwe
fi

sudo update-grub

cat <<'EOF'

================================================================
Camera setup done, but it needs a REBOOT INTO THE HWE KERNEL!

The camera will not work on the System76 kernel: no PSYS module.
GRUB's first entry ("Pop OS") is always a kernel that has PSYS,
so just take the default.

Reboot, then pick GRUB from the firmware boot menu (F12 on this
Dell) rather than letting it boot the old default. Check that the
Minecraft menu draws, Windows is listed, and it boots. Then:

    uname -r                                       # want: *-generic
    ls /dev/ipu-psys0
    systemctl status v4l2-relayd@default.service   # want: active (running)
    wpctl status                                   # want: one camera

Only once that all checks out, make GRUB the default:

    sudo efibootmgr -v | grep -i grub              # note its BootXXXX
    sudo efibootmgr -o <GRUB>,<rEFInd>,<systemd-boot>,...

To undo, drop GRUB back down that list. rEFInd and systemd-boot
are both left installed precisely so that works.

Then open a NEW shell so the toolchain hooks take effect.
================================================================
EOF
