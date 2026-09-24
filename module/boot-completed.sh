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

_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
_seen=$(cat "$DATA/.bootdone" 2>/dev/null)
[ -n "$_boot" ] && [ "$_boot" = "$_seen" ] && exit 0
[ -n "$_boot" ] && echo "$_boot" > "$DATA/.bootdone"

[ "$enabled" = 0 ] && { dk_describe; exit 0; }

dk_dns_apply
dk_susfs_refresh
dk_describe

if dk_sched_due; then
    if [ "$wifi_only" = 1 ] && ! dk_on_wifi; then
        dk_log "[*] update is due but the phone is not on Wi-Fi"
    else
        dk_log "[+] scheduled update is due, running it now"
        dk_lock_acquire && { dk_build; dk_lock_release; }
    fi
fi
