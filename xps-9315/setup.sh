#!/bin/bash
# Hardware setup for the Dell XPS 13 Plus 9315 on Pop!_OS 24.04: the IPU6
# webcam and the kernel it needs, the sof_sdw audio topology, this disk's
# recovery partition, and GRUB. ../restart.sh runs it after the portable half
# when it detects the machine; it is also fine to run on its own, or re-run.
#
# Not set -e, same as ../restart.sh. The README covers the reasoning.
set -uo pipefail

DOWNLOADS="$(mktemp -d)"
trap 'rm -rf "$DOWNLOADS"' EXIT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Audio node names, panel resolution and partition uuids are all this laptop's
PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [ "$PRODUCT" != "XPS 9315" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "xps-9315: DMI reports '${PRODUCT:-unknown}', not 'XPS 9315'. Re-run with FORCE=1 to override."
    exit 1
fi

# ---------------------------------------------------------------------------
# recovery partition (nvme0n1p6)
# ---------------------------------------------------------------------------

# pop-upgrade finds the partition by looking for /recovery in /proc/mounts, so
# unmounted it reports no recovery partition at all. Refresh the image with
# `sudo pop-upgrade recovery upgrade from-release 24.04`; the boot entry comes
# from grub-shortmenu.sh, since pop-upgrade only registers one with systemd-boot
sudo mkdir -p /recovery
if ! grep -q '/recovery' /etc/fstab; then
    echo 'UUID=7C59-13DD  /recovery  vfat  defaults,nofail  0  0' | sudo tee -a /etc/fstab > /dev/null
    sudo systemctl daemon-reload
    sudo mount -a
fi

# ---------------------------------------------------------------------------
# camera (Intel IPU6 / ov01a10)
#
# A MIPI sensor, not USB, running through Intel's HAL rather than libcamera:
#   ov01a10 -> intel_ipu6_isys + intel_ipu6_psys (kernel)
#           -> libcamhal / icamerasrc -> v4l2-relayd -> v4l2loopback
#           -> /dev/video0 -> apps
#
# Do NOT install libcamera0.2 / libcamera-tools / gstreamer1.0-libcamera: none
# of this goes through libcamera, and the PipeWire plugin breaks Cheese
# ---------------------------------------------------------------------------

sudo add-apt-repository -y ppa:oem-solutions-group/intel-ipu6

# libcamhal-ipu6ep, NOT libcamhal-ipu6ep0: the trailing-zero package is an
# empty stub and gives "failed to open library: .../ipu6ep.so"
sudo apt install -y v4l-utils cheese \
    libcamhal0 libcamhal-ipu6ep libcamhal-ipu6ep-common \
    gstreamer1.0-icamera v4l2-relayd

# PSYS was never upstreamed and only ships as modules matched to Ubuntu kernel
# ABIs, so System76's kernel has ISYS but no PSYS. Meta packages, so kernel and
# modules always upgrade together
sudo apt install -y linux-generic-hwe-24.04 linux-modules-ipu6-generic-hwe-24.04

# Otherwise initramfs-tools treats the random-key cryptswap as a resume target
# and hangs at boot. That swap can never be resumed from anyway
echo 'RESUME=none' | sudo tee /etc/initramfs-tools/conf.d/resume
sudo update-initramfs -u -k all

# Hide the 32 raw ISYS nodes from PipeWire clients, leaving the v4l2loopback
# device ("Intel MIPI Camera"). README: Raw ISYS nodes
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

# Firefox enumerates /dev/video* itself, and the raw nodes are openable by
# anyone in the video group. Opening one wedges ISYS and freezes calls on a
# still frame. Lock them to root; v4l2-relayd runs as root, and /dev/video0
# reports a different ID_V4L_PRODUCT so it is never matched
sudo tee /etc/udev/rules.d/73-hide-ipu6-raw-nodes.rules >/dev/null <<'EOF'
SUBSYSTEM=="video4linux", ENV{ID_V4L_PRODUCT}=="ipu6", GROUP="root", MODE="0660", TAG-="uaccess"
EOF
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=video4linux
# After the trigger, not before: it re-creates the nodes and their stale ACLs
sudo setfacl -b /dev/video{1..32} 2>/dev/null

# v4l2-relayd is Restart=always with no RestartSec, so a briefly busy camera
# burns the 5-in-10s limit in two seconds and stays dead needing reset-failed
sudo mkdir -p /etc/systemd/system/v4l2-relayd@default.service.d
sudo tee /etc/systemd/system/v4l2-relayd@default.service.d/override.conf >/dev/null <<'EOF'
[Unit]
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
RestartSec=2
EOF
sudo systemctl daemon-reload

# ---------------------------------------------------------------------------
# audio (sof_sdw: rt714 mic array, Blue Yeti, HDMI sinks)
# ---------------------------------------------------------------------------

# WirePlumber picks the highest priority.session sink, and the Blue Yeti's
# headphone jack (1109) outranks the earbuds (1010) and speakers (712), so
# audio kept landing in a microphone. Its capture node is untouched.
# Match api.alsa.card.name, not alsa.card_name, which is added too late to fire
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

# Windows enables the rt714 mic boost and Linux leaves it at 0, which is why
# the internal mic is so quiet. Boost before the ADC, since the PipeWire source
# has no headroom left. By name, not numid: numids shift with the topology
amixer -c sofsoundwire cset name='rt714 FU0C Boost' 2,2,2,2,2,2,2,2
amixer -c sofsoundwire cset name='rt714 FU0E Boost' 2,2,2,2,2,2,2,2

# Or the levels are gone at the next boot
sudo alsactl store 0

# If rEFInd is still installed, keep its default on a PSYS kernel. No-ops when
# refind.conf is absent
if [ -f "$HERE/refind-default-hwe.sh" ]; then
    sudo install -m 0755 "$HERE/refind-default-hwe.sh" /etc/kernel/postinst.d/zz-refind-default-hwe
    sudo /etc/kernel/postinst.d/zz-refind-default-hwe
fi

# ---------------------------------------------------------------------------
# bootloader: GRUB with the minegrub theme
#
# A deliberate swap: Pop ships systemd-boot and recommends against GRUB. apt
# removes grub-pc on the way in, which is expected. This does NOT reorder the
# firmware boot entries; boot GRUB by hand first, then run the efibootmgr line
# printed at the end. rEFInd and systemd-boot stay installed as fallbacks
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
# Native panel resolution. Set to `auto` if the menu is garbled or 640x480
grub_set GRUB_GFXMODE 1920x1200
grub_set GRUB_GFXPAYLOAD_LINUX keep
grub_set GRUB_DISABLE_OS_PROBER false
grub_set GRUB_CMDLINE_LINUX_DEFAULT '"quiet loglevel=0 systemd.show_status=false splash"'
grub_set GRUB_THEME /boot/grub/themes/minegrub/theme.txt

# minegrub, skipping their install_theme.sh: it also wires up a systemd service
# that rewrites the splash from fastfetch output on every boot
git clone --depth 1 https://github.com/Lxtharia/minegrub-theme.git "$DOWNLOADS/minegrub"
sudo rm -rf /boot/grub/themes/minegrub
sudo mkdir -p /boot/grub/themes
sudo cp -r "$DOWNLOADS/minegrub/minegrub" /boot/grub/themes/

# The bottom bar sits at a hardcoded offset keyed to the number of top-level
# entries: 4 is 314, 5 is 386, 6 is 458, one 72px row a step. 09_shortmenu
# emits 5. Theme state, so no update-grub, but it has to move if that count does
sudo sed -i 's|^\ttop = 40%+314$|\ttop = 40%+386|' /boot/grub/themes/minegrub/theme.txt
grep -q 'top = 40%+386' /boot/grub/themes/minegrub/theme.txt \
    || echo "minegrub: bottom bar offset not applied, check theme.txt" >&2

# Short titles, since the stock generators overflow minegrub's 600px buttons.
# 09_shortmenu also puts the PSYS kernel first, so GRUB_DEFAULT=0 pins the
# camera kernel. README: Short menu titles
if [ -f "$HERE/grub-shortmenu.sh" ]; then
    sudo install -m 0755 "$HERE/grub-shortmenu.sh" /etc/grub.d/09_shortmenu
    for gen in 10_linux 10_linux_zfs 20_linux_xen 30_os-prober 30_uefi-firmware 35_fwupd; do
        [ -f "/etc/grub.d/$gen" ] && sudo chmod -x "/etc/grub.d/$gen"
    done
fi

# Belt and braces: keeps the PSYS kernel at entry 0 via GRUB_TOP_LEVEL if
# 09_shortmenu is ever disabled and 10_linux re-enabled
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
================================================================
EOF
