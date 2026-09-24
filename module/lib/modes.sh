DK_MODES="nomount susfs_redirect zn_redirect ap_redirect ksud_umount susfs_bind overlay bind mount"

dk_mode_label_set() {
    case "$1" in
        nomount)        DK_MODE_LABEL="NoMount injection" ;;
        susfs_redirect) DK_MODE_LABEL="SUSFS open_redirect" ;;
        zn_redirect)    DK_MODE_LABEL="ZN hostsredirect" ;;
        ap_redirect)    DK_MODE_LABEL="APatch hosts_file_redirect" ;;
        ksud_umount)    DK_MODE_LABEL="bind + ksud kernel umount" ;;
        susfs_bind)     DK_MODE_LABEL="bind + SUSFS autobind" ;;
        overlay)        DK_MODE_LABEL="overlayfs on /system/etc" ;;
        bind)           DK_MODE_LABEL="plain bind mount" ;;
        mount)          DK_MODE_LABEL="manager magic mount" ;;
        *)              DK_MODE_LABEL=$1 ;;
    esac
    case "$1" in
        nomount|susfs_redirect|zn_redirect|ap_redirect|ksud_umount|susfs_bind) DK_MODE_HIDDEN=1 ;;
        *) DK_MODE_HIDDEN=0 ;;
    esac
    return 0
}

dk_mode_label() {
    case "$1" in
        nomount)        echo "NoMount injection" ;;
        susfs_redirect) echo "SUSFS open_redirect" ;;
        zn_redirect)    echo "ZN hostsredirect" ;;
        ap_redirect)    echo "APatch hosts_file_redirect" ;;
        ksud_umount)    echo "bind + ksud kernel umount" ;;
        susfs_bind)     echo "bind + SUSFS autobind" ;;
        overlay)        echo "overlayfs on /system/etc" ;;
        bind)           echo "plain bind mount" ;;
        mount)          echo "manager magic mount" ;;
        *)              echo "$1" ;;
    esac
}

dk_mode_hidden() {
    case "$1" in
        nomount|susfs_redirect|zn_redirect|ap_redirect|ksud_umount|susfs_bind) echo 1 ;;
        *) echo 0 ;;
    esac
}

dk_mode_valid() {
    case " $DK_MODES " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

dk_zygisk_denylist_handler() {
    for m in rezygisk zygisk-assistant zygisk_nohello; do
        dk_module_live "$m" && { echo "$m"; return 0; }
    done
    if dk_module_live zygisksu; then
        grep -q "NeoZygisk" /data/adb/modules/zygisksu/module.prop 2>/dev/null &&
            { echo NeoZygisk; return 0; }
        _e=$(cat /data/adb/zygisksu/denylist_enforce 2>/dev/null)
        case "$_e" in
            1|2) echo "ZygiskNext"; return 0 ;;
        esac
    fi
    return 1
}

dk_mode_probe() {
    _mode=mount
    _reason="manager serves the module tree"

    if [ "$KSU" = true ] && [ ! "$KSU_MAGIC_MOUNT" = true ]; then
        _mode=bind
        _reason="overlayfs manager, hosts bound in place"
    fi

    if _h=$(dk_zygisk_denylist_handler); then
        _mode=bind
        _reason="$_h unmounts for denylisted apps"
    fi

    if dk_susfs_has CONFIG_KSU_SUSFS_TRY_UMOUNT; then
        _mode=susfs_bind
        _reason="SUSFS try_umount available"
    fi

    if [ "$KSU" = true ] && ksud kernel 2>&1 | grep -q umount; then
        _mode=ksud_umount
        _reason="ksud kernel umount available"
    fi

    if [ "$APATCH" = true ] && dmesg 2>/dev/null | grep -q hosts_file_redirect; then
        _mode=ap_redirect
        _reason="APatch kernel hosts_file_redirect active"
    fi

    if dk_module_live hostsredirect && dk_module_live zygisksu; then
        _mode=zn_redirect
        _reason="zn-hostsredirect installed"
    fi

    if dk_susfs_has CONFIG_KSU_SUSFS_OPEN_REDIRECT; then
        _mode=susfs_redirect
        _reason="SUSFS open_redirect available, no mount needed"
    fi

    if dk_nomount_dir > /dev/null 2>&1; then
        _mode=nomount
        _reason="NoMount metamodule injects the hosts file"
    fi

    DK_MODE=$_mode
    DK_MODE_REASON=$_reason
}

dk_mode_resolve() {
    dk_mode_probe
    DK_MODE_AUTO=$DK_MODE
    DK_MODE_AUTO_REASON=$DK_MODE_REASON
    if [ -n "$mode" ] && [ "$mode" != auto ]; then
        if dk_mode_valid "$mode"; then
            DK_MODE=$mode
            DK_MODE_REASON="forced in settings"
        else
            dk_log "[!] unknown mode '$mode' in settings, using $DK_MODE_AUTO"
        fi
    fi
    DK_HOSTS=$MODDIR/system/etc/hosts
    case "$DK_MODE" in
        zn_redirect) DK_PUBLISH=/data/adb/hostsredirect/hosts ;;
        ap_redirect) DK_PUBLISH=/data/adb/hosts ;;
        *) DK_PUBLISH= ;;
    esac
}

dk_mode_save() {
    {
        echo "mode_active='$DK_MODE'"
        echo "mode_auto='$DK_MODE_AUTO'"
        echo "mode_reason='$(echo "$DK_MODE_REASON" | tr -d "'")'"
        echo "hosts_target='$DK_HOSTS'"
        echo "hosts_publish='$DK_PUBLISH'"
    } > "$DATA/mode.sh"
    chmod 0600 "$DATA/mode.sh" 2>/dev/null
}

dk_mode_load() {
    if [ -f "$DATA/mode.sh" ]; then
        . "$DATA/mode.sh"
        DK_MODE=$mode_active
        DK_MODE_AUTO=$mode_auto
        DK_MODE_REASON=$mode_reason
        DK_HOSTS=$hosts_target
        DK_PUBLISH=$hosts_publish
    fi
    [ -n "$DK_MODE" ] || dk_mode_resolve
    [ -n "$DK_HOSTS" ] || DK_HOSTS=$MODDIR/system/etc/hosts
    return 0
}

dk_publish() {
    [ -n "$DK_PUBLISH" ] || return 0
    _d=${DK_PUBLISH%/*}
    mkdir -p "$_d" 2>/dev/null
    cat "$DK_HOSTS" > "$DK_PUBLISH" 2>/dev/null || {
        dk_log "[x] could not write $DK_PUBLISH"
        return 1
    }
    dk_set_perm "$DK_PUBLISH"
}

dk_bind_hosts() {
    mountpoint -q /system/etc/hosts 2>/dev/null && return 0
    mount --bind "$DK_HOSTS" /system/etc/hosts 2>/dev/null || {
        dk_log "[x] bind mount failed"
        return 1
    }
}

dk_overlay_hosts() {
    _dev=overlay
    [ "$KSU" = true ] && _dev=KSU
    [ "$APATCH" = true ] && _dev=APatch
    mkdir -p "$MODDIR/workdir"
    mount -t overlay -o "lowerdir=/system/etc,upperdir=$MODDIR/system/etc,workdir=$MODDIR/workdir" \
        "$_dev" /system/etc 2>/dev/null || {
        dk_log "[x] overlay mount failed"
        return 1
    }
}

dk_susfs_autobind() {
    [ -x "$SUSFS_BIN" ] || return 0
    case "$1" in
        redirect)
            "$SUSFS_BIN" add_open_redirect /system/etc/hosts "$DK_HOSTS" 2 > /dev/null 2>&1 ||
                "$SUSFS_BIN" add_open_redirect /system/etc/hosts "$DK_HOSTS" > /dev/null 2>&1
            ;;
        bind)
            dk_susfs_has CONFIG_KSU_SUSFS_SUS_KSTAT &&
                "$SUSFS_BIN" update_sus_kstat /system/etc/hosts > /dev/null 2>&1
            dk_susfs_has CONFIG_KSU_SUSFS_SUS_MOUNT &&
                "$SUSFS_BIN" add_sus_mount /system/etc/hosts > /dev/null 2>&1
            "$SUSFS_BIN" add_try_umount /system/etc/hosts 1 > /dev/null 2>&1 ||
                "$SUSFS_BIN" add_try_umount /system/etc/hosts > /dev/null 2>&1
            ;;
        overlay)
            dk_susfs_has CONFIG_KSU_SUSFS_SUS_MOUNT &&
                "$SUSFS_BIN" add_sus_mount /system/etc > /dev/null 2>&1
            "$SUSFS_BIN" add_try_umount /system/etc 1 > /dev/null 2>&1 ||
                "$SUSFS_BIN" add_try_umount /system/etc > /dev/null 2>&1
            ;;
    esac
    return 0
}

dk_susfs_refresh() {
    [ -x "$SUSFS_BIN" ] || return 0
    [ -f "$DATA/mode.sh" ] && . "$DATA/mode.sh"
    case "${mode_active:-$DK_MODE}" in
        susfs_redirect)
            "$SUSFS_BIN" add_open_redirect /system/etc/hosts "$DK_HOSTS" 2 > /dev/null 2>&1 ||
                "$SUSFS_BIN" add_open_redirect /system/etc/hosts "$DK_HOSTS" > /dev/null 2>&1
            ;;
        susfs_bind|ksud_umount|bind)
            dk_susfs_has CONFIG_KSU_SUSFS_SUS_KSTAT &&
                "$SUSFS_BIN" update_sus_kstat /system/etc/hosts > /dev/null 2>&1
            ;;
    esac
    return 0
}

dk_mode_apply() {
    case "$DK_MODE" in
        nomount)
            dk_log "[+] NoMount metamodule serves the hosts file, nothing mounted"
            ;;
        mount)
            dk_log "[+] manager magic-mounts the module tree"
            ;;
        susfs_redirect)
            dk_susfs_autobind redirect
            dk_log "[+] SUSFS open_redirect armed"
            ;;
        susfs_bind)
            dk_susfs_has CONFIG_KSU_SUSFS_SUS_KSTAT &&
                "$SUSFS_BIN" add_sus_kstat /system/etc/hosts > /dev/null 2>&1
            dk_bind_hosts || return 1
            dk_susfs_autobind bind
            dk_log "[+] bound with SUSFS autobind"
            ;;
        ksud_umount)
            dk_bind_hosts || return 1
            ksud kernel umount add /system/etc/hosts --flags 2 > /dev/null 2>&1
            dk_susfs_autobind bind
            dk_log "[+] bound, ksud kernel umount registered"
            ;;
        bind)
            dk_bind_hosts || return 1
            dk_susfs_autobind bind
            dk_log "[+] bound"
            ;;
        overlay)
            dk_overlay_hosts || return 1
            dk_susfs_autobind overlay
            dk_log "[+] overlay mounted on /system/etc"
            ;;
        zn_redirect|ap_redirect)
            dk_publish
            dk_log "[+] published to $DK_PUBLISH"
            ;;
    esac
    return 0
}

dk_skip_mount() {
    case "$DK_MODE" in
        nomount|mount) rm -f "$MODDIR/skip_mount" 2>/dev/null ;;
        *) : > "$MODDIR/skip_mount" 2>/dev/null ;;
    esac
}
