#!/bin/bash
# Post-install setup for Pop!_OS 24.04, written against Ubuntu 24.04 (noble)
# repos. Nothing here is tied to a particular machine
#
# Not set -e on purpose: the sections are independent, so one dead repo should
# not abort the rest. Grouped by what the software is for, not by installer.
# Third-party repos go in right before the install that needs them
set -uo pipefail

DOWNLOADS="$(mktemp -d)"
trap 'rm -rf "$DOWNLOADS"' EXIT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Append to ~/.bashrc only if the marker is absent, so re-runs do not duplicate.
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
# ---------------------------------------------------------------------------

sudo apt update && sudo apt full-upgrade -y

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ---------------------------------------------------------------------------
# desktop & system
# ---------------------------------------------------------------------------

sudo apt install -y gnome-tweaks gnome-shell-extension-manager gnome-shell-extensions

# adw-gtk3 (the GTK3 theme matching libadwaita's look) and cosmic-icons ship
# with Pop!_OS already, but naming them explicitly keeps this working on a
# plain Ubuntu base too
sudo apt install -y adw-gtk3 cosmic-icons

# dash-to-dock. pop-shell (tiling) is already part of Pop!_OS's base image;
# dash-to-dock is not, so it has to come from extensions.gnome.org. The API
# call resolves the current download for whatever shell version is
# installed, so this doesn't need re-pinning every GNOME release
SHELL_VERSION="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
DTD_JSON="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=dash-to-dock@micxgx.gmail.com&shell_version=$SHELL_VERSION")"
DTD_PATH="$(printf '%s' "$DTD_JSON" | python3 -c 'import json, sys; print(json.load(sys.stdin)["download_url"])')"
wget -O "$DOWNLOADS/dash-to-dock.zip" "https://extensions.gnome.org$DTD_PATH"
gnome-extensions install --force "$DOWNLOADS/dash-to-dock.zip"
gnome-extensions enable dash-to-dock@micxgx.gmail.com
gnome-extensions enable pop-shell@system76.com

# Theme, dock position/size, button layout, wallpaper, and the taskbar
# favorites. Deliberately doesn't touch app-picker-layout (the app grid's
# icon order): that key is a snapshot of every app installed on one machine
# at one point in time, so reproducing it just scatters icons around missing
# apps on a fresh install instead of leaving them in the grid's default order
mkdir -p "$HOME/.local/share/backgrounds"
cp "$HERE/gnome/2026-05-21-21-36-46-Matterhorn At Night.jpg" "$HOME/.local/share/backgrounds/"
dconf load / < "$HERE/gnome/settings.ini"

sudo apt install -y sqlite3 rsync locate openssh-server smartmontools \
    tlp tlp-rdw

# The proton deb only drops in the repo, so the client needs an update first
wget -P "$DOWNLOADS" https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb
sudo dpkg -i "$DOWNLOADS/protonvpn-stable-release_1.0.8_all.deb"
sudo apt update
sudo apt install -y proton-vpn-gnome-desktop

# rEFInd, a fallback boot path alongside the GRUB setup in xps-9315/
# sudo add-apt-repository -y ppa:rodsmith/refind
#sudo apt install -y refind

# ---------------------------------------------------------------------------
# storage & drives
# ---------------------------------------------------------------------------

sudo apt install -y ntfs-3g

# Preference list, not a fallback chain: udisks takes the first driver it
# supports and never retries. "ntfs" means ntfs-3g, so ntfs3 has to lead to be
# preferred. Deliberate: a dirty volume then fails loudly. README: Storage
sudo mkdir -p /etc/udisks2
sudo tee /etc/udisks2/mount_options.conf > /dev/null <<'EOF'
[defaults]
ntfs_drivers=ntfs3,ntfs
EOF

sudo systemctl restart udisks2

# Seagate Portable Drive, the Jellyfin media library. Re-check the uuid with
# `blkid` if the drive is replaced. The timeout and the docker ordering both
# stop the library from silently coming up empty; README: Docker and Jellyfin
sudo mkdir -p /mnt/media
if ! grep -q '/mnt/media' /etc/fstab; then
    echo 'UUID=620C6DA000E97169  /mnt/media  ntfs-3g  uid=1000,gid=1000,umask=022,nofail,x-systemd.device-timeout=30s,x-systemd.before=docker.service  0  0' | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
    sudo mount -a
fi

# Pika's own config needs the GUI (passphrase, drive). Its exclude list is
# worth reproducing by hand; README: Backups
sudo flatpak install -y flathub org.gnome.World.PikaBackup

# ---------------------------------------------------------------------------
# development
# ---------------------------------------------------------------------------

sudo apt install -y code git-all gh adb

sudo flatpak install -y flathub com.getpostman.Postman

# Adds a key to VS Code's settings.json if not already present, leaving
# everything else (including // comments, which VS Code allows there but a
# JSON parser would strip) untouched: this inserts a line after the opening
# brace instead of parsing the file.
CODE_SETTINGS="$HOME/.config/Code/User/settings.json"
code_setting_set() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "$CODE_SETTINGS")"
    [ -f "$CODE_SETTINGS" ] || echo '{}' > "$CODE_SETTINGS"
    if ! grep -qF "\"$key\":" "$CODE_SETTINGS"; then
        python3 - "$CODE_SETTINGS" "$key" "$value" <<'EOF'
import sys
path, key, value = sys.argv[1:4]
with open(path) as f:
    text = f.read()
idx = text.index('{') + 1
text = text[:idx] + f'\n  "{key}": {value},' + text[idx:]
with open(path, 'w') as f:
    f.write(text)
EOF
    fi
}

# GNOME's default Droid Sans Mono hasn't shipped in years; fontconfig
# resolves it to proportional Noto Sans, which Chromium (VS Code's renderer)
# rejects as a non-matching substitute and falls through to a serif face
# instead of a monospace one. This bites with terminal GPU acceleration on:
# the software path happens to pick a usable fallback, the GPU path doesn't.
# Naming fonts that are actually installed (below) fixes both editor and
# terminal.
code_setting_set "editor.fontFamily" "\"'DejaVu Sans Mono', monospace\""
code_setting_set "terminal.integrated.fontFamily" "\"'DejaVu Sans Mono', 'Symbols Nerd Font Mono', monospace\""
code_setting_set "terminal.integrated.gpuAcceleration" '"on"'

# docker. Runs Jellyfin and most of the repos under ~/Documents/projects.
# Pop is Ubuntu-based but VERSION_CODENAME is its own, so pin to noble
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
# Needs a re-login (or `newgrp docker`) to apply
sudo usermod -aG docker "$USER"

# latex. The useful subset; texlive-full works too but is ~6 GB
sudo apt install -y latexmk biber chktex \
    texlive-latex-recommended texlive-latex-extra \
    texlive-fonts-recommended texlive-fonts-extra \
    texlive-science texlive-pictures texlive-extra-utils

# --- toolchains ---
# Per-user installs under $HOME, not apt. Each needs its ~/.bashrc hook or it
# is not on PATH in a new shell

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

# rbenv (ruby). Build deps for ruby-build; jekyll and bundler come from `gem`
# under rbenv, since rbenv init shadows the apt ruby
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

sudo apt install -y mpv audacity qbittorrent imagemagick ffmpegthumbnailer

sudo flatpak install -y flathub \
    com.spotify.Client com.github.johnfactotum.Foliate

# jellyfin. A container, not an apt package; compose.yaml is committed
# separately, bind-mounts /mnt/media read-only and needs /dev/dri
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

# Valve's deb by path, not `apt install steam`: Pop ships a different package
# of the same name at priority 1001 with a different Steam root. This one is
# the client and brings its own repo in. README: Steam
wget -P "$DOWNLOADS" https://repo.steampowered.com/steam/archive/stable/steam.deb
sudo apt install -y "$DOWNLOADS/steam.deb"

sudo apt install -y cockatrice curseforge

# Migrating off Pop's steam leaves a dangling ~/.local .desktop link, which
# shadows the working system one and hides the app entirely. README: Steam
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

sudo apt install -y thunderbird zoom

# signal ships its own repo
wget -O- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor | sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null
wget -O- https://updates.signal.org/static/desktop/apt/signal-desktop.sources | sudo tee /etc/apt/sources.list.d/signal-desktop.sources > /dev/null
sudo apt update
sudo apt install -y signal-desktop

sudo flatpak install -y flathub com.discordapp.Discord

# ---------------------------------------------------------------------------
# terminal: kitty, fonts, prompt
# ---------------------------------------------------------------------------

sudo apt install -y kitty

# JetBrains Mono (kitty's font_family) and the Nerd Font symbols-only font
# (kitty's symbol_map, Starship's icons, VS Code's terminal fallback below).
# Neither ships as an apt package; both are per-user installs under
# ~/.local/share/fonts, same as the toolchains above.
if [ ! -d "$HOME/.local/share/fonts/JetBrainsMono" ]; then
    wget -P "$DOWNLOADS" https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip
    mkdir -p "$HOME/.local/share/fonts/JetBrainsMono"
    unzip -o -j "$DOWNLOADS/JetBrainsMono-2.304.zip" 'fonts/ttf/*' -d "$HOME/.local/share/fonts/JetBrainsMono"
fi
if [ ! -d "$HOME/.local/share/fonts/NerdFontsSymbols" ]; then
    wget -P "$DOWNLOADS" https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/NerdFontsSymbolsOnly.zip
    mkdir -p "$HOME/.local/share/fonts/NerdFontsSymbols"
    unzip -o -j "$DOWNLOADS/NerdFontsSymbolsOnly.zip" '*.ttf' -d "$HOME/.local/share/fonts/NerdFontsSymbols"
fi
fc-cache -f "$HOME/.local/share/fonts" > /dev/null

# kitty.conf, dark-theme.auto.conf (kitty's own light/dark auto-switching -
# see the comment in that file) and the last Pokemon-Terminal background
mkdir -p "$HOME/.config/kitty"
cp "$HERE/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
cp "$HERE/kitty/dark-theme.auto.conf" "$HOME/.config/kitty/dark-theme.auto.conf"
cp "$HERE/kitty/pokemon_bg.jpg" "$HOME/.config/kitty/pokemon_bg.jpg"

# pokemon-terminal, the kitty background picker. Installed as a uv tool
# rather than pip/pipx since uv is already the toolchain of choice above;
# $HOME/.local/bin isn't necessarily on PATH yet within this script, so call
# it by its full path just this once.
"$HOME/.local/bin/uv" tool install pokemon-terminal

# kitty-pokemon-sync: not a pokemon-terminal entry point, so `uv tool
# install` above won't create it. Needs pokemonterminal importable, which
# only exists inside that tool's own venv, hence the shebang rewrite instead
# of a plain #!/usr/bin/env python3. README: Terminal
install -Dm755 "$HERE/kitty/kitty-pokemon-sync" "$HOME/.local/bin/kitty-pokemon-sync"
sed -i "1s|^#!.*|#!$HOME/.local/share/uv/tools/pokemon-terminal/bin/python|" "$HOME/.local/bin/kitty-pokemon-sync"

bashrc_once 'pokemon() {' <<EOF

# kitty.conf points background_image at pokemon_bg.jpg (a stable path); this
# keeps that file in sync with whatever \`pokemon\` last picked, by forcing -v
# to learn the chosen name (normally only printed in verbose/dry-run mode)
# and suppressing the noisy per-candidate list that -v also adds.
pokemon() {
    case " \$* " in
        *' -c '*|*' --clear '*)
            command pokemon "\$@"
            local status=\$?
            rm -f "\$HOME/.config/kitty/pokemon_bg.jpg"
            return \$status
            ;;
    esac
    local out chosen
    # unset KITTY_WINDOW_ID here: without this, Pokemon-Terminal's own kitty
    # backend sets the live background itself first, from the RAW uncropped
    # image - then our corrected push below immediately overwrites it, so
    # the image visibly jumps twice per pick. Unsetting it makes it think it
    # isn't running in kitty, so it skips that step and only our version
    # ever renders. \$(...) is already a subshell, so this doesn't touch the
    # real value in the rest of this shell.
    out=\$(unset KITTY_WINDOW_ID; command pokemon -v "\$@" 2>&1)
    local status=\$?
    chosen=\$(printf '%s\n' "\$out" | grep -E '^Total of [0-9]+ pokemon matched the filters\. Chose ' | tail -1)
    if [ -n "\$chosen" ]; then
        echo "\$chosen"
        kitty-pokemon-sync "\${chosen#*Chose }" 2>/dev/null
        kitty @ set-background-image "\$HOME/.config/kitty/pokemon_bg.jpg" >/dev/null 2>&1
    else
        printf '%s\n' "\$out"
    fi
    return \$status
}
EOF

# Starship prompt (catppuccin-powerline preset, Mocha flavor - matches the
# kitty theme). Installed to ~/.local/bin, not system-wide.
curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
mkdir -p "$HOME/.config"
cp "$HERE/starship/starship.toml" "$HOME/.config/starship.toml"

bashrc_once 'eval "$(starship init bash)"' <<'EOF'

# Starship prompt (catppuccin-powerline preset, Mocha flavor - matches the
# kitty theme). Installed to ~/.local/bin, not system-wide. This overrides
# PS1 dynamically via PROMPT_COMMAND on every prompt, so it doesn't matter
# that the PS1 set earlier in this file runs first - starship replaces it
# regardless of ordering, unlike SDKMAN above which genuinely needs to be
# last.
export PATH="$HOME/.local/bin:$PATH"
eval "$(starship init bash)"
EOF

# ---------------------------------------------------------------------------
# shell: update aliases (up, updown, upstart)
# ---------------------------------------------------------------------------

bashrc_once '_up_step()' <<'EOF'

# update aliases
# Colored headers only when stdout is a terminal, so piping `up` into a file
# does not litter it with escape codes.
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

cat <<'EOF'

================================================================
Portable setup done. Open a NEW shell so the toolchain hooks
(uv, rustup, elan, nvm, rbenv) take effect, and re-login once so
the docker group applies.
================================================================
EOF

# ---------------------------------------------------------------------------
# hardware
# Machine-specific setup lives next to this script and only runs on the machine
# it was written for. Run it by hand with FORCE=1 to override the DMI check.
# Add a new machine by dropping a <dir>/setup.sh next to this file and a case
# arm below mapping its DMI product_name to that directory.
# ---------------------------------------------------------------------------

PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
case "$PRODUCT" in
    "XPS 9315")  HW_DIR="xps-9315" ;;
    "82D2")      HW_DIR="ideapad-82d2" ;;
    *)           HW_DIR="" ;;
esac

if [ -n "$HW_DIR" ]; then
    if [ -x "$HERE/$HW_DIR/setup.sh" ]; then
        "$HERE/$HW_DIR/setup.sh"
    else
        echo "hardware: $HW_DIR/setup.sh missing or not executable, skipping"
    fi
else
    echo "hardware: DMI reports '${PRODUCT:-unknown}', no matching machine dir, skipping"
fi
