SKIPUNZIP=0
MODDIR=$MODPATH
. "$MODPATH/lib/common.sh"

VER=$(sed -n 's/^version=//p' "$MODPATH/module.prop")
ui_print ""
ui_print "  DuckAds $VER"
ui_print "  systemless ad blocking"
ui_print ""

if [ "$BOOTMODE" != true ]; then
    ui_print "! install DuckAds from KernelSU, APatch, Magisk or MMRL"
    ui_print "! recovery installs cannot probe the injection mode"
    abort
fi

if [ "$KSU" = true ]; then
    ui_print "- manager: KernelSU (code $KSU_VER_CODE, kernel $KSU_KERNEL_VER_CODE)"
elif [ "$APATCH" = true ]; then
    ui_print "- manager: APatch (code $APATCH_VER_CODE)"
elif [ -n "$MAGISK_VER_CODE" ]; then
    ui_print "- manager: Magisk $MAGISK_VER_CODE"
else
    ui_print "! unknown root manager, continuing anyway"
fi

dk_seed
dk_load_conf
dk_snapshot_orig

mkdir -p "$MODPATH/system/etc"
if [ -s /data/adb/modules/duckads/system/etc/hosts ]; then
    ui_print "- keeping the hosts file from the previous install"
    cat /data/adb/modules/duckads/system/etc/hosts > "$MODPATH/system/etc/hosts"
else
    cat "$DATA/hosts.orig" > "$MODPATH/system/etc/hosts" 2>/dev/null
fi
dk_set_perm "$MODPATH/system/etc/hosts"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/duckads.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/boot-completed.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
dk_set_perm "$MODPATH/system/etc/hosts"

for d in /data/adb/ap/bin /data/adb/ksu/bin; do
    [ -d "$d" ] && ln -sf /data/adb/modules/duckads/duckads.sh "$d/duckads" 2>/dev/null &&
        ui_print "- terminal command installed: duckads"
done

conflict=0
for m in /data/adb/modules/*; do
    id=${m##*/}
    [ "$id" = duckads ] && continue
    [ -f "$m/system/etc/hosts" ] || continue
    [ -f "$m/disable" ] && continue
    touch "$m/disable" 2>/dev/null
    ui_print "! conflicting hosts module disabled: $id"
    conflict=1
done
[ "$conflict" = 1 ] && ui_print "! reboot is required for that to take effect"

if pm path org.adaway > /dev/null 2>&1; then
    ui_print "! AdAway is installed - reset its hosts file or the two will fight"
fi

. "$MODPATH/lib/modes.sh"
dk_mode_resolve
ui_print "- injection mode: $DK_MODE ($(dk_mode_label "$DK_MODE"))"
ui_print "  $DK_MODE_REASON"
[ "$(dk_mode_hidden "$DK_MODE")" = 1 ] &&
    ui_print "- this mode hides the hosts file from detection" ||
    ui_print "! this mode leaves a visible mount - see the README"

ui_print ""
ui_print "- reboot, then open the module's WebUI and hit Update"
ui_print "- or run: duckads --update"
ui_print ""
