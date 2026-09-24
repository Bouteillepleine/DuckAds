#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/modes.sh"

dk_seed
dk_log_rotate

{
    echo "KSU='${KSU:-false}'"
    echo "KSU_NEXT='${KSU_NEXT:-false}'"
    echo "KSU_VER_CODE='${KSU_VER_CODE:-0}'"
    echo "KSU_KERNEL_VER_CODE='${KSU_KERNEL_VER_CODE:-0}'"
    echo "KSU_MAGIC_MOUNT='${KSU_MAGIC_MOUNT:-false}'"
    echo "APATCH='${APATCH:-false}'"
    echo "APATCH_BIND_MOUNT='${APATCH_BIND_MOUNT:-false}'"
    echo "APATCH_VER_CODE='${APATCH_VER_CODE:-0}'"
    echo "MAGISK_VER_CODE='${MAGISK_VER_CODE:-}'"
} > "$ENVFILE"
chmod 0600 "$ENVFILE" 2>/dev/null

dk_load_conf
dk_snapshot_orig

mkdir -p "$MODDIR/system/etc"
if [ ! -s "$MODDIR/system/etc/hosts" ]; then
    cat "$DATA/hosts.orig" > "$MODDIR/system/etc/hosts" 2>/dev/null
fi
dk_set_perm "$MODDIR/system/etc/hosts"

dk_mode_resolve
dk_mode_save
dk_skip_mount

for m in /data/adb/modules/*; do
    id=${m##*/}
    [ "$id" = duckads ] && continue
    [ -f "$m/system/etc/hosts" ] || continue
    [ -f "$m/disable" ] && continue
    [ -f "$m/remove" ] && continue
    touch "$m/disable" 2>/dev/null
    dk_kmsg "disabled conflicting hosts module: $id"
    dk_log "[!] disabled conflicting hosts module: $id"
done

dk_kmsg "post-fs-data: mode=$DK_MODE ($DK_MODE_REASON)"
dk_log "[+] boot: mode=$DK_MODE ($DK_MODE_REASON)"
