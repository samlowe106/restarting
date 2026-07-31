#!/bin/sh
# Point GRUB's default menu entry at the newest kernel that actually has the
# Intel IPU6 PSYS module, so the webcam keeps working across kernel upgrades.
#
# Background: PSYS was never upstreamed. It only ships as prebuilt modules
# matched to Ubuntu kernel ABIs (linux-modules-ipu6-*). System76's Pop kernel
# has ISYS but no PSYS, and its version sorts ABOVE the Ubuntu HWE kernel, so
# without this the default drifts back to a kernel where the camera is dead.
#
# Uses GRUB_TOP_LEVEL rather than GRUB_DEFAULT. /etc/grub.d/10_linux feeds it
# to grub_move_to_front, which makes that kernel the top-level entry and pushes
# the rest into "Advanced options". GRUB_DEFAULT=0 then selects it. A generated
# menuentry id would work too, but it embeds the ABI version and breaks on the
# next bump; a path does not.
#
# Install as /etc/kernel/postinst.d/zz-grub-default-hwe (mode 0755). It sorts
# before zz-update-grub, so grub.cfg is regenerated with the new value in the
# same kernel install. Also safe to run by hand, but then run update-grub too.
#
# Always exits 0: a bootloader tweak must never fail a kernel installation.

set -u

GRUB_DEFAULT_FILE=/etc/default/grub

[ -f "$GRUB_DEFAULT_FILE" ] || { echo "grub-default-hwe: $GRUB_DEFAULT_FILE not found, skipping"; exit 0; }

# Newest installed kernel that ships intel-ipu6-psys.
best=""
for img in /boot/vmlinuz-*; do
    [ -f "$img" ] || continue
    ver=${img#/boot/vmlinuz-}
    # ls glob rather than -f, because the extension varies (.ko, .ko.zst, ...)
    if ls "/lib/modules/$ver/ubuntu/ipu6/intel-ipu6-psys.ko"* >/dev/null 2>&1; then
        if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "$best" "$ver" | sort -V | tail -1)" = "$ver" ]; then
            best=$ver
        fi
    fi
done

if [ -z "$best" ]; then
    echo "grub-default-hwe: no installed kernel has intel-ipu6-psys, leaving default alone"
    exit 0
fi

target="/boot/vmlinuz-$best"

# Already correct? Then do nothing, so we do not rewrite the file on every install.
if grep -qE "^GRUB_TOP_LEVEL=\"?$target\"?$" "$GRUB_DEFAULT_FILE"; then
    echo "grub-default-hwe: GRUB_TOP_LEVEL already $target"
    exit 0
fi

cp -a "$GRUB_DEFAULT_FILE" "$GRUB_DEFAULT_FILE.bak" 2>/dev/null || true
sed -i '/^[[:space:]]*GRUB_TOP_LEVEL=/d' "$GRUB_DEFAULT_FILE" 2>/dev/null || true
printf 'GRUB_TOP_LEVEL="%s"\n' "$target" >> "$GRUB_DEFAULT_FILE" 2>/dev/null || {
    echo "grub-default-hwe: could not write $GRUB_DEFAULT_FILE"
    exit 0
}

echo "grub-default-hwe: GRUB_TOP_LEVEL set to $target"
exit 0
