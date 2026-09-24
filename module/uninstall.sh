#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/dns.sh"
. "$MODDIR/lib/sched.sh"

dk_load_conf
dk_dns_clear
dk_sched_stop

for d in /data/adb/ap/bin /data/adb/ksu/bin /sbin /debug_ramdisk; do
    [ -L "$d/duckads" ] && rm -f "$d/duckads" 2>/dev/null
done

for f in state mode.sh env.sh sources.stat hosts.bak .bootdone duckads.log; do
    rm -f "$DATA/$f" 2>/dev/null
done
rm -rf "$DATA/.lock" "$DATA/crontabs" 2>/dev/null

dk_kmsg "uninstalled - rules and settings kept in $DATA"
