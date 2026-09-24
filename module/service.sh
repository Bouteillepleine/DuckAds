#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/modes.sh"
. "$MODDIR/lib/engine.sh"
. "$MODDIR/lib/dns.sh"
. "$MODDIR/lib/exempt.sh"
. "$MODDIR/lib/sched.sh"

dk_load_conf
dk_mode_load

for d in /data/adb/ap/bin /data/adb/ksu/bin; do
    [ -d "$d" ] && ln -sf "$MODDIR/duckads.sh" "$d/duckads" 2>/dev/null
done
if [ "$KSU" != true ] && [ "$APATCH" != true ]; then
    [ -w /sbin ] && magisktmp=/sbin
    [ -w /debug_ramdisk ] && magisktmp=/debug_ramdisk
    [ -n "$magisktmp" ] && ln -sf "$MODDIR/duckads.sh" "$magisktmp/duckads" 2>/dev/null
fi

if [ "$enabled" = 0 ]; then
    dk_log "[*] blocking is paused in settings"
    dk_kmsg "service: paused"
    dk_describe
else
    dk_mode_apply
    dk_dns_apply
    dk_exempt_reconcile
fi

dk_sched_apply

if [ "$KSU" = true ]; then
    ksud kernel notify-module-mounted > /dev/null 2>&1
fi

(
    _n=0
    while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$_n" -lt 180 ]; do
        sleep 1
        _n=$((_n + 1))
    done
    sh "$MODDIR/boot-completed.sh"
) &
