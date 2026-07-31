#!/bin/sh
# Point rEFInd's default_selection at the newest kernel that actually has the
# Intel IPU6 PSYS module, so the webcam keeps working across kernel upgrades.
#
# Background: PSYS was never upstreamed. It only ships as prebuilt modules
# matched to Ubuntu kernel ABIs (linux-modules-ipu6-*). System76's Pop kernel
# has ISYS but no PSYS, and its version sorts ABOVE the Ubuntu HWE kernel, so
# without this the default drifts back to a kernel where the camera is dead.
#
# Install as /etc/kernel/postinst.d/zz-refind-default-hwe (mode 0755) and it
# re-runs automatically on every kernel install. Also safe to run by hand.
#
# Always exits 0: a bootloader tweak must never fail a kernel installation.

set -u

REFIND_CONF=/boot/efi/EFI/refind/refind.conf

[ -f "$REFIND_CONF" ] || { echo "refind-default-hwe: $REFIND_CONF not found, skipping"; exit 0; }

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
    echo "refind-default-hwe: no installed kernel has intel-ipu6-psys, leaving default alone"
    exit 0
fi

target="vmlinuz-$best"

# Already correct? Then do nothing, so we do not churn the ESP on every install.
if grep -qE "^[[:space:]]*default_selection[[:space:]]+\"?$target\"?[[:space:]]*$" "$REFIND_CONF"; then
    echo "refind-default-hwe: default already $target"
    exit 0
fi

cp -a "$REFIND_CONF" "$REFIND_CONF.bak" 2>/dev/null || true
sed -i '/^[[:space:]]*default_selection/d' "$REFIND_CONF" 2>/dev/null || true
printf '\ndefault_selection "%s"\n' "$target" >> "$REFIND_CONF" 2>/dev/null || {
    echo "refind-default-hwe: could not write $REFIND_CONF"
    exit 0
}

echo "refind-default-hwe: default_selection set to $target"
exit 0
