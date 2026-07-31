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

# refind. Boots this machine instead of systemd-boot; see the kernel hook at
# the bottom for keeping the default on a camera-capable kernel
# sudo add-apt-repository -y ppa:rodsmith/refind
#sudo apt install -y refind

# ---------------------------------------------------------------------------
# storage & drives
# ---------------------------------------------------------------------------

sudo apt install -y ntfs-3g

sudo mkdir -p /etc/udisks2
sudo tee /etc/udisks2/mount_options.conf > /dev/null <<'EOF'
[defaults]
ntfs_drivers=ntfs,ntfs3
EOF

sudo systemctl restart udisks2

# Seagate Portable Drive, the Jellyfin media library. UUID is specific to that
# physical disk, so re-check with `blkid` if the drive is ever replaced.
sudo mkdir -p /mnt/media
if ! grep -q '/mnt/media' /etc/fstab; then
    echo 'UUID=620C6DA000E97169  /mnt/media  ntfs-3g  uid=1000,gid=1000,umask=022,nofail,x-systemd.device-timeout=10s  0  0' | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
    sudo mount -a
fi

# backups
sudo flatpak install -y flathub org.gnome.World.PikaBackup

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
# ---------------------------------------------------------------------------

sudo apt install -y steam cockatrice curseforge

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

# The 32 raw IPU6 ISYS nodes (/dev/video1-32) get enumerated by PipeWire but
# cannot be opened (libcamhal-common's udev rule strips their uaccess ACL)
# Apps that pick one fail with "error set output format: -22". Hide them so
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
systemctl --user restart wireplumber

# Keep rEFInd defaulting to a kernel that actually has PSYS, including after
# future kernel upgrades. Installed as a kernel postinst hook so it re-runs
# automatically whenever apt installs a kernel.
if [ -f "$(dirname "$0")/refind-default-hwe.sh" ]; then
    sudo install -m 0755 "$(dirname "$0")/refind-default-hwe.sh" /etc/kernel/postinst.d/zz-refind-default-hwe
    sudo /etc/kernel/postinst.d/zz-refind-default-hwe
fi

cat <<'EOF'

================================================================
Camera setup done, but it needs a REBOOT INTO THE HWE KERNEL!

The camera will not work on the System76 kernel: no PSYS module.
In rEFInd each kernel is its own top-level icon (F2/Insert shows
cmdline variants, not a kernel list). Pick the *-generic HWE one.

Verify after rebooting:
    uname -r
    ls /dev/ipu-psys0
    systemctl status v4l2-relayd@default.service   # want: active (running)
    wpctl status                                   # want: one camera

Then open a NEW shell so the toolchain hooks take effect.
================================================================
EOF
