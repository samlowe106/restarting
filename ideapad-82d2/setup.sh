#!/bin/bash
# Hardware setup for the Lenovo IdeaPad Slim 9 14ITL5 (system model 82D2) on
# Pop!_OS 24.04. ../restart.sh runs it after the portable half when it
# detects the machine; it is also fine to run on its own, or re-run.
#
# Unlike xps-9315/setup.sh, this one is not yet backed by a real Linux boot
# on this hardware -- it was written from the Windows-side device inventory
# below, before the first install. Treat everything past the DMI check as a
# checklist, not a guarantee: run it, work through "First boot checklist" at
# the bottom, and turn whatever actually breaks into a real fix here, the
# same way xps-9315/setup.sh grew out of actual bugs on that machine.
#
# Not set -e, same as ../restart.sh. The README covers the reasoning.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Known hardware (Windows System Information, 2026-09-19)
# ---------------------------------------------------------------------------
# CPU      Intel Core i7-1165G7 (Tiger Lake, 4C/8T)
# GPU      Intel Iris Xe, integrated only -- no discrete GPU, so none of the
#          Nvidia/optimus driver story applies here
# Wi-Fi    Intel Wi-Fi 6 AX201 -- iwlwifi, in-kernel, no DKMS driver needed
#          (contrast the Realtek chips a lot of IdeaPads ship instead)
# Audio    Intel Smart Sound Technology (SST) DSP + Realtek HD Audio codec --
#          needs SOF firmware, which Ubuntu ships by default. Speaker/mic
#          quirks, if any, are unknown until this is actually booted
# Display  3840x2160 (4K) on a 14" panel, so GNOME's default 100% scaling
#          will be too small; fractional scaling is the fix, see below
# BIOS     UEFI, Secure Boot ON, LENOVO ESCN56WW (6/28/2022)
# Disk     single NVMe SSD, ~475 GB total, dual-booting alongside Windows

PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [ "$PRODUCT" != "82D2" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "ideapad-82d2: DMI reports '${PRODUCT:-unknown}', not '82D2'. Re-run with FORCE=1 to override."
    exit 1
fi

# ---------------------------------------------------------------------------
# display: fractional scaling for the 4K panel
# ---------------------------------------------------------------------------

# Fractional scaling is still behind an experimental flag on GNOME/Wayland.
# This only unlocks the slider in Settings > Displays; pick 150/175/200% by
# eye once logged in, whatever reads best on a 14" panel at this density.
#
# This machine boots to COSMIC by default, which sandboxes dconf/gsettings
# writes into a separate "cosmic" profile (see restart.sh's dash-to-dock/
# dconf section for the full explanation). Force the plain "user" profile so
# this actually lands where a GNOME session will see it.
env -u DCONF_PROFILE gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"

# ---------------------------------------------------------------------------
# battery: conservation mode
# ---------------------------------------------------------------------------

# ideapad_laptop ships in the mainline kernel, no package needed. It exposes
# Lenovo's charge threshold (stops around 60-80% instead of 100%) as a sysfs
# node under a VPC* instance whose exact name varies by ACPI numbering, hence
# the find. Worth it on a machine that lives on AC most of the time.
CONSERVE="$(find /sys/bus/platform/drivers/ideapad_acpi -maxdepth 1 -name 'VPC*' 2>/dev/null | head -1)/conservation_mode"
if [ -e "$CONSERVE" ]; then
    echo 1 | sudo tee "$CONSERVE" > /dev/null
    echo "ideapad-82d2: battery conservation mode on ($CONSERVE)"
else
    echo "ideapad-82d2: conservation_mode sysfs node not found -- check 'ls /sys/bus/platform/drivers/ideapad_acpi/'"
fi

# ---------------------------------------------------------------------------
# keyboard: bind the PrtSc key's bare (no-Fn) action to gnome-screenshot
# ---------------------------------------------------------------------------

# On the XPS, Print already launches a usable screenshot flow out of the box.
# On this keyboard, the key between Insert and Delete is dual-purpose: it's
# silkscreened with a scissors/snip icon as its bare (no-Fn) action and
# "PrtSc" as its Fn-combo action, on the same physical row as F1-F12 so
# Hotkey Mode applies to it too. Fn+key does send the literal Print keysym
# (keycode 107), but the bare press does not -- it's a hardware macro of
# Windows' own Snipping Tool shortcut, Super+Shift+S. xev only ever shows the
# `Shift+S` tail of it because GNOME Shell grabs Super globally for the
# Activities overview before any X11 client sees the press. Binding the
# custom shortcut to that combo (rather than 'Print', or flipping fn_lock and
# changing every other F-row key's default behavior) makes the bare press
# work with the smallest possible change.
#
# Same DCONF_PROFILE caveat as restart.sh's dash-to-dock/dconf section: this
# machine boots to COSMIC by default, which sandboxes dconf/gsettings writes
# into a separate profile a GNOME session never reads.
env -u DCONF_PROFILE gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
    "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"
env -u DCONF_PROFILE gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'gnome-screenshot'
env -u DCONF_PROFILE gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'gnome-screenshot -i'
env -u DCONF_PROFILE gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Shift><Super>s'

cat <<'EOF'

================================================================
ideapad-82d2: done with what's known ahead of time. First boot
checklist -- work through these, then fold whatever's actually
broken into a real fix in this script (see the note up top):

    Wi-Fi        nmcli device status                # want: AX201, connected
    Bluetooth    bluetoothctl show                   # want: Powered: yes
    Audio out    wpctl status                        # want: speakers listed
                 speaker-test -c2                     # want: audible, both channels
    Mic          arecord -d 3 t.wav && aplay t.wav
    Webcam       cheese                               # if this machine has one
    Fn keys      brightness / volume / airplane-mode from the keyboard
    HiDPI        Settings > Displays, try 150/175/200% fractional scaling
    Secure Boot  mokutil --sb-state                    # want: SecureBoot enabled
    Dual boot    confirm Windows shows in the boot menu
================================================================
EOF
