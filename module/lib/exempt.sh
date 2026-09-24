dk_exempt_mech_set() {
    [ -n "$DK_MECH" ] && return 0
    if dk_nomount_bin > /dev/null 2>&1; then
        DK_MECH=nomount
    elif dk_have ksud && ksud profile --help 2>&1 | grep -q "set"; then
        DK_MECH=ksud
    elif dk_have magisk && magisk --denylist status > /dev/null 2>&1; then
        DK_MECH=magisk
    else
        DK_MECH=none
    fi
    case "$DK_MECH" in
        nomount) DK_MECH_LABEL="NoMount per-uid hide list" ;;
        ksud)    DK_MECH_LABEL="KernelSU app profile (umount modules)" ;;
        magisk)  DK_MECH_LABEL="Magisk denylist" ;;
        *)       DK_MECH_LABEL="not available on this setup" ;;
    esac
    return 0
}

dk_exempt_mech() {
    if dk_nomount_bin > /dev/null 2>&1; then
        echo nomount
        return 0
    fi
    if dk_have ksud && ksud profile --help 2>&1 | grep -q "set"; then
        echo ksud
        return 0
    fi
    if dk_have magisk && magisk --denylist status > /dev/null 2>&1; then
        echo magisk
        return 0
    fi
    echo none
    return 1
}

dk_exempt_mech_label() {
    case "$1" in
        nomount) echo "NoMount per-uid hide list" ;;
        ksud)    echo "KernelSU app profile (umount modules)" ;;
        magisk)  echo "Magisk denylist" ;;
        *)       echo "not available on this setup" ;;
    esac
}

dk_pkg_valid() {
    case "$1" in
        ''|*[!A-Za-z0-9._]*) return 1 ;;
    esac
    case "$1" in
        *.*) return 0 ;;
    esac
    return 1
}

dk_exempt_set() {
    _pkg=$1
    _on=$2
    dk_pkg_valid "$_pkg" || { dk_log "[x] not a package name: $_pkg"; return 1; }
    _mech=$(dk_exempt_mech)
    case "$_mech" in
        nomount)
            _b=$(dk_nomount_bin) || return 1
            _nm=$(echo "$_b" | sed 's|nomount$|nm|')
            if [ "$_on" = 1 ]; then
                NM_BIN=$_nm "$_b" uid block "$_pkg" > /dev/null 2>&1
            else
                NM_BIN=$_nm "$_b" uid unblock "$_pkg" > /dev/null 2>&1
            fi
            ;;
        ksud)
            if [ "$_on" = 1 ]; then
                printf '{"key":"%s","allow_su":false,"non_root":{"use_default":false,"umount_modules":true}}\n' "$_pkg" |
                    ksud profile set > /dev/null 2>&1
            else
                printf '{"key":"%s","allow_su":false,"non_root":{"use_default":true,"umount_modules":false}}\n' "$_pkg" |
                    ksud profile set > /dev/null 2>&1
            fi
            ;;
        magisk)
            if [ "$_on" = 1 ]; then
                magisk --denylist add "$_pkg" > /dev/null 2>&1
            else
                magisk --denylist rm "$_pkg" > /dev/null 2>&1
            fi
            ;;
        *)
            dk_log "[x] no per-app mechanism on this setup"
            return 1
            ;;
    esac
    _rc=$?
    if [ "$_rc" != 0 ]; then
        dk_log "[x] $_mech refused the change for $_pkg"
        return 1
    fi
    touch "$DATA/exempt.list"
    grep -v "^$_pkg\$" "$DATA/exempt.list" > "$DATA/exempt.tmp" 2>/dev/null
    [ "$_on" = 1 ] && echo "$_pkg" >> "$DATA/exempt.tmp"
    mv -f "$DATA/exempt.tmp" "$DATA/exempt.list"
    chmod 0600 "$DATA/exempt.list" 2>/dev/null
    dk_log "[+] $_pkg $([ "$_on" = 1 ] && echo exempted || echo "back under blocking") via $_mech"
    return 0
}

dk_exempt_reconcile() {
    [ "$exempt_enabled" = 1 ] || return 0
    [ -s "$DATA/exempt.list" ] || return 0
    _mech=$(dk_exempt_mech)
    [ "$_mech" = none ] && return 0
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        dk_pkg_valid "$pkg" || continue
        DK_QUIET=1 dk_exempt_set "$pkg" 1
    done < "$DATA/exempt.list"
    return 0
}

dk_exempt_list() {
    [ -f "$DATA/exempt.list" ] && grep -v "^\$" "$DATA/exempt.list" 2>/dev/null
    return 0
}
