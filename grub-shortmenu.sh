#!/bin/sh
# Short-title GRUB menu generator, for use with a themed menu.
#
# Install as /etc/grub.d/09_shortmenu (mode 0755), then chmod -x the stock
# generators it replaces:
#
#   10_linux 10_linux_zfs 20_linux_xen 30_os-prober 30_uefi-firmware 35_fwupd
#
# Why: minegrub's button pixmaps are 600px wide and the theme sets font size
# 30, but the stock generators emit titles like "Windows Boot Manager (on
# /dev/nvme0n1p1)" and "Advanced options for Pop!_OS GNU/Linux". Long text in a
# fixed-width Minecraft button is what reads as broken. This emits four short
# titles instead. It also drops "!" and "_" from names, which the Minecraft pf2
# fonts do not carry a glyph for.
#
# The first entry is always the newest kernel that ships intel-ipu6-psys, which
# is what the Intel IPU6 webcam needs. With GRUB_DEFAULT=0 that makes the pin
# structural rather than something a sort order can undo. GRUB_TOP_LEVEL in
# /etc/default/grub is unused while this file is active, but is left in place so
# the pin still holds if 10_linux is ever re-enabled.
#
# Reversal: chmod -x this file, chmod +x the six above, run update-grub.

set -e

# Windows ESP. Re-check with `lsblk -f` if Windows is ever reinstalled; the
# entry is silently skipped if this filesystem is not present.
WIN_ESP_UUID=1802-B5C9
WIN_EFI=/EFI/Microsoft/Boot/bootmgfw.efi

# Pop recovery partition (nvme0n1p6), the full reinstall image. Not the same
# thing as the per-kernel "(recovery)" entries in the Advanced submenu below:
# those are ordinary single-user boots of the installed system, this one boots a
# live image that can reinstall it. The entry is silently skipped if the
# partition is not present.
#
# Refresh the image with `sudo pop-upgrade recovery upgrade from-release <ver>`.
# That needs the partition mounted at /recovery, which is what the fstab entry
# for this uuid is for. pop-upgrade finds the partition by looking for /recovery
# in /proc/mounts, so without that mount it reports no recovery partition at all
# rather than saying the mount is missing.
RECOVERY_UUID=7C59-13DD

ROOT_UUID=$(grub-probe --target=fs_uuid / 2>/dev/null) || {
    echo "09_shortmenu: grub-probe could not determine the root fs uuid" >&2
    exit 1
}

CMDLINE="${GRUB_CMDLINE_LINUX_DEFAULT:-quiet splash} ${GRUB_CMDLINE_LINUX:-}"

# All installed kernels, newest first.
kernels=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's,^/boot/vmlinuz-,,' | sort -Vr)
[ -n "$kernels" ] || { echo "09_shortmenu: no kernels in /boot" >&2; exit 1; }

# Newest kernel that ships intel-ipu6-psys, so the webcam works. Falls back to
# the newest kernel overall rather than emitting nothing.
best=""
for ver in $kernels; do
    if ls "/lib/modules/$ver/ubuntu/ipu6/intel-ipu6-psys.ko"* >/dev/null 2>&1; then
        best=$ver
        break
    fi
done
if [ -z "$best" ]; then
    best=$(echo "$kernels" | head -1)
    echo "09_shortmenu: no kernel has intel-ipu6-psys, defaulting to $best" >&2
else
    echo "09_shortmenu: default kernel $best (has intel-ipu6-psys)" >&2
fi

emit_linux() {
    # $1 title, $2 kernel version, $3 extra cmdline
    cat <<EOF
menuentry '$1' --class pop_os --class gnu-linux --class gnu --class os {
	load_video
	set gfxpayload=keep
	insmod gzio
	insmod part_gpt
	insmod ext2
	search --no-floppy --fs-uuid --set=root $ROOT_UUID
	linux /boot/vmlinuz-$2 root=UUID=$ROOT_UUID $3
	initrd /boot/initrd.img-$2
}
EOF
}

# "ro" is not optional: the initramfs mounts root read-only so fsck can run
# against it, and systemd remounts it rw afterwards. GRUB_CMDLINE_LINUX_DEFAULT
# does not carry it, 10_linux adds it separately, so this has to add it too.
emit_linux "Pop OS" "$best" "ro $CMDLINE vt.handoff=7"

if blkid -U "$WIN_ESP_UUID" >/dev/null 2>&1; then
    cat <<EOF
menuentry 'Windows' --class windows --class os {
	insmod part_gpt
	insmod fat
	insmod chain
	search --no-floppy --fs-uuid --set=root $WIN_ESP_UUID
	chainloader $WIN_EFI
}
EOF
else
    echo "09_shortmenu: no filesystem with uuid $WIN_ESP_UUID, skipping Windows" >&2
fi

# The kernel arguments below are copied from boot/grub/grub.cfg inside the Pop
# recovery ISO itself, so they are what Pop ships rather than a reconstruction.
# The only change is the casper directory name: the ISO ships it as
# casper_pop-os_<version>_..., and pop-upgrade renames it to casper-<fs uuid>
# when it syncs onto the partition, which is why it lines up with RECOVERY_UUID.
#
# insmod fat, not ext2, because the recovery partition is vfat. The kernel is
# loaded from the partition rather than the copy pop-upgrade puts in
# /boot/efi/EFI/Recovery-<uuid>/, so this keeps working if the ESP copy is lost.
if blkid -U "$RECOVERY_UUID" >/dev/null 2>&1; then
    cat <<EOF
menuentry 'Recovery' --class pop_os --class gnu-linux --class gnu --class os {
	load_video
	set gfxpayload=keep
	insmod gzio
	insmod part_gpt
	insmod fat
	search --no-floppy --fs-uuid --set=root $RECOVERY_UUID
	linux /casper-$RECOVERY_UUID/vmlinuz.efi boot=casper live-media-path=/casper-$RECOVERY_UUID hostname=pop-os username=pop-os noprompt quiet splash ---
	initrd /casper-$RECOVERY_UUID/initrd.gz
}
EOF
else
    echo "09_shortmenu: no filesystem with uuid $RECOVERY_UUID, skipping Recovery" >&2
fi

echo "submenu 'Advanced' \$menuentry_id_option 'shortmenu-advanced' {"
for ver in $kernels; do
    emit_linux "$ver" "$ver" "ro $CMDLINE vt.handoff=7" | sed 's,^,\t,'
    emit_linux "$ver (recovery)" "$ver" "ro recovery nomodeset dis_ucode_ldr" | sed 's,^,\t,'
done
echo "}"

cat <<'EOF'
if [ "$grub_platform" = "efi" ]; then
	fwsetup --is-supported
	if [ "$?" = 0 ]; then
		menuentry 'Firmware Settings' --class uefi-firmware {
			fwsetup
		}
	fi
fi
EOF
