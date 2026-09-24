MODID=duckads
DK_ROOT=${DK_ROOT:-}
MODDIR=${MODDIR:-$DK_ROOT/data/adb/modules/$MODID}
DATA=$DK_ROOT/data/adb/$MODID
LOGFILE=$DATA/duckads.log
CONF=$DATA/config.sh
STATE=$DATA/state
ENVFILE=$DATA/env.sh
for _s in /data/adb/ksu/bin/ksu_susfs /data/adb/ap/bin/ksu_susfs /data/adb/ksu/bin/susfs; do
    [ -x "$_s" ] && SUSFS_BIN=$_s && break
done
SUSFS_BIN=${SUSFS_BIN:-/data/adb/ksu/bin/ksu_susfs}
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
export PATH

DK_QUIET=${DK_QUIET:-0}
DK_JSON=${DK_JSON:-0}

dk_versioncode() {
    dk_prop_load
    echo "$DK_VCODE"
}

dk_prop_load() {
    [ -n "$DK_VCODE" ] && return 0
    DK_VCODE=0
    DK_VERSION=""
    while IFS='=' read -r _pk _pv; do
        case "$_pk" in
            versionCode) DK_VCODE=$_pv ;;
            version) DK_VERSION=$_pv ;;
        esac
    done < "$MODDIR/module.prop" 2>/dev/null
    case "$DK_VCODE" in ''|*[!0-9]*) DK_VCODE=0 ;; esac
    return 0
}

dk_esc() {
    case "$1" in
        *\\*|*\"*|*'	'*|*'
'*) DK_E=$(printf '%s' "$1" | sed -e 's|\\|\\\\|g' -e 's|"|\\"|g' -e 's|	|\\t|g' | tr -d '\r\n') ;;
        *) DK_E=$1 ;;
    esac
}

dk_kmsg() {
    echo "duckads: $*" > /dev/kmsg 2>/dev/null
}

dk_log() {
    [ -d "$DATA" ] && echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOGFILE" 2>/dev/null
    [ "$DK_QUIET" = 1 ] && return 0
    if [ "$DK_JSON" = 1 ]; then
        echo "$*" >&2
    else
        echo "$*"
    fi
}

dk_log_rotate() {
    [ -f "$LOGFILE" ] || return 0
    _sz=$(stat -c %s "$LOGFILE" 2>/dev/null || echo 0)
    case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
    [ "$_sz" -lt 262144 ] && return 0
    tail -n 400 "$LOGFILE" > "$LOGFILE.tmp" 2>/dev/null && mv -f "$LOGFILE.tmp" "$LOGFILE" 2>/dev/null
    rm -f "$LOGFILE.tmp" 2>/dev/null
}

dk_defaults() {
    enabled=1
    mode=auto
    sink=0.0.0.0
    ipv6_sink=0
    max_entries=0
    keep_system_hosts=1
    update_schedule=weekly
    update_cron=
    update_hour=4
    update_rate_limit=0
    wifi_only=1
    doh_block=0
    doh_strict=0
    doh_dot=1
    exempt_enabled=1
    notify=1
    lists_seeded=0
}

dk_load_conf() {
    dk_defaults
    [ -f "$CONF" ] && . "$CONF"
    [ -f "$ENVFILE" ] && . "$ENVFILE"
    return 0
}

dk_conf_keys() {
    echo "enabled mode sink ipv6_sink max_entries keep_system_hosts update_schedule update_cron update_hour update_rate_limit wifi_only doh_block doh_strict doh_dot exempt_enabled notify lists_seeded"
}

dk_cfg_set() {
    _k=$1
    _v=$2
    case " $(dk_conf_keys) " in
        *" $_k "*) ;;
        *) dk_log "[x] unknown setting: $_k"; return 1 ;;
    esac
    case "$_v" in
        *[\`\$\;\&\|\<\>\'\"]*|*'
'*) dk_log "[x] rejected value for $_k"; return 1 ;;
    esac
    mkdir -p "$DATA"
    touch "$CONF"
    dk_kv_put "$CONF" "$_k" "'$_v'"
    chmod 0600 "$CONF" 2>/dev/null
}

dk_kv_put() {
    _file=$1
    awk -v k="$2" -v v="$3" '
        BEGIN { done = 0 }
        index($0, k "=") == 1 { if (!done) { print k "=" v; done = 1 } next }
        { print }
        END { if (!done) print k "=" v }
    ' "$_file" > "$_file.tmp" 2>/dev/null && mv -f "$_file.tmp" "$_file"
    rm -f "$_file.tmp" 2>/dev/null
}

dk_state_set() {
    mkdir -p "$DATA"
    touch "$STATE"
    dk_kv_put "$STATE" "$1" "$2"
}

dk_state_get() {
    [ -f "$STATE" ] || return 0
    sed -n "s|^$1=||p" "$STATE" 2>/dev/null | head -n1
}

dk_state_load() {
    [ -f "$STATE" ] || return 0
    while IFS='=' read -r _k _v; do
        case "$_k" in
            ''|*[!a-z_]*) continue ;;
        esac
        eval "DKS_$_k=\$_v"
    done < "$STATE"
    return 0
}

dk_state_num() {
    eval "DK_N=\${DKS_$1}"
    case "$DK_N" in
        ''|*[!0-9]*) DK_N=${2:-0} ;;
    esac
    echo "$DK_N"
}

dk_set_perm() {
    [ -n "$1" ] || return 0
    chmod 0644 "$1" 2>/dev/null
    chown 0:0 "$1" 2>/dev/null
    chcon u:object_r:system_file:s0 "$1" 2>/dev/null ||
        busybox chcon --reference=/system/etc/hosts "$1" 2>/dev/null
}

dk_have() {
    command -v "$1" > /dev/null 2>&1
}

dk_abi() {
    getprop ro.product.cpu.abi 2>/dev/null || echo arm64-v8a
}

dk_nomount_dir() {
    _d=$(readlink -f /data/adb/metamodule 2>/dev/null)
    case "${_d##*/}" in
        nomount|meta-nomount) ;;
        *) _d="" ;;
    esac
    if [ -z "$_d" ]; then
        for _c in /data/adb/modules/meta-nomount /data/adb/modules/nomount; do
            [ -d "$_c" ] && _d=$_c && break
        done
    fi
    [ -n "$_d" ] || return 1
    [ -f "$_d/disable" ] && return 1
    [ -f "$_d/remove" ] && return 1
    echo "$_d"
}

dk_nomount_bin() {
    _d=$(dk_nomount_dir) || return 1
    _b=$_d/bin/$(dk_abi)/nomount
    [ -x "$_b" ] || return 1
    echo "$_b"
}

dk_nomount_reload() {
    _b=$(dk_nomount_bin) || return 0
    _nm=$(echo "$_b" | sed 's|nomount$|nm|')
    NM_BIN=$_nm "$_b" reload > /dev/null 2>&1
    return 0
}

dk_susfs_features() {
    [ -x "$SUSFS_BIN" ] || return 1
    if [ -z "$DK_SUSFS_FEAT" ]; then
        DK_SUSFS_FEAT=$("$SUSFS_BIN" show enabled_features 2>/dev/null)
        [ -n "$DK_SUSFS_FEAT" ] || DK_SUSFS_FEAT=none
    fi
    [ "$DK_SUSFS_FEAT" = none ] && return 1
    echo "$DK_SUSFS_FEAT"
}

dk_susfs_has() {
    dk_susfs_features 2>/dev/null | grep -q "$1"
}

dk_module_live() {
    [ -d "/data/adb/modules/$1" ] &&
        [ ! -f "/data/adb/modules/$1/disable" ] &&
        [ ! -f "/data/adb/modules/$1/remove" ]
}

dk_seed() {
    mkdir -p "$DATA" "$DATA/crontabs"
    chmod 0700 "$DATA" 2>/dev/null
    for f in blacklist.txt whitelist.txt custom.txt exempt.list doh.local; do
        [ -f "$DATA/$f" ] || : > "$DATA/$f"
    done
    [ -f "$DATA/sources.list" ] || dk_seed_sources
    [ -f "$CONF" ] || { : > "$CONF"; chmod 0600 "$CONF" 2>/dev/null; }
}

dk_seed_sources() {
    : > "$DATA/sources.list"
    while IFS='	' read -r id kind cat name def url note; do
        [ -n "$id" ] || continue
        case "$id" in \#*) continue ;; esac
        [ "$def" = 1 ] || continue
        echo "on|$kind|$id|$url|$name" >> "$DATA/sources.list"
    done < "$MODDIR/data/catalog.tsv"
    chmod 0600 "$DATA/sources.list" 2>/dev/null
}

dk_snapshot_orig() {
    mkdir -p "$DATA"
    if [ -f "$DATA/hosts.orig" ] && ! grep -q DuckAds "$DATA/hosts.orig" 2>/dev/null; then
        return 0
    fi
    if [ -r /system/etc/hosts ] && ! grep -q DuckAds /system/etc/hosts 2>/dev/null; then
        cat /system/etc/hosts > "$DATA/hosts.orig" 2>/dev/null
    else
        printf '127.0.0.1 localhost\n::1 ip6-localhost\n' > "$DATA/hosts.orig" 2>/dev/null
    fi
    chmod 0600 "$DATA/hosts.orig" 2>/dev/null
}

dk_orig_lines() {
    [ "$keep_system_hosts" = 1 ] || return 0
    [ -r "$DATA/hosts.orig" ] || return 0
    grep -vE '^[[:space:]]*($|#)' "$DATA/hosts.orig" 2>/dev/null |
        grep -v DuckAds |
        grep -vE '^(127\.0\.0\.1|::1)[ 	]+(localhost|localhost\.localdomain)[ 	]*$' |
        sed 's/\r$//'
}

dk_lock_acquire() {
    _lockdir=$DATA/.lock
    _n=0
    while ! mkdir "$_lockdir" 2>/dev/null; do
        _old=$(cat "$_lockdir/pid" 2>/dev/null)
        case "$_old" in
            ''|*[!0-9]*) rm -rf "$_lockdir" 2>/dev/null; continue ;;
        esac
        if [ ! -d "/proc/$_old" ]; then
            rm -rf "$_lockdir" 2>/dev/null
            continue
        fi
        _n=$((_n + 1))
        [ "$_n" -gt 60 ] && { dk_log "[x] another DuckAds run (pid $_old) holds the lock"; return 1; }
        sleep 1
    done
    echo $$ > "$_lockdir/pid" 2>/dev/null
    return 0
}

dk_lock_release() {
    rm -rf "$DATA/.lock" 2>/dev/null
}

dk_json_str() {
    case "$1" in
        *\\*|*\"*|*'	'*|*'
'*) printf '%s' "$1" | sed -e 's|\\|\\\\|g' -e 's|"|\\"|g' -e 's|	|\\t|g' | tr -d '\r\n' ;;
        *) printf '%s' "$1" ;;
    esac
}

dk_tmpdir() {
    for d in "$DATA" "$DK_ROOT/data/local/tmp" "$DK_ROOT/dev"; do
        [ -d "$d" ] || continue
        if mkdir "$d/.dkprobe.$$" 2>/dev/null; then
            rmdir "$d/.dkprobe.$$" 2>/dev/null
            echo "$d"
            return 0
        fi
    done
    echo "$DATA"
}

dk_manager_name() {
    DK_MANAGER=$(dk_manager_name_raw)
    echo "$DK_MANAGER"
}

dk_manager_name_set() {
    [ -n "$DK_MANAGER" ] && return 0
    if [ "$APATCH" = true ]; then DK_MANAGER=APatch
    elif [ "$KSU_NEXT" = true ]; then DK_MANAGER="KernelSU Next"
    elif [ "$KSU" = true ]; then DK_MANAGER=KernelSU
    elif [ -n "$MAGISK_VER_CODE" ]; then DK_MANAGER=Magisk
    elif dk_have ksud; then DK_MANAGER=KernelSU
    elif [ -f /data/adb/apd ]; then DK_MANAGER=APatch
    elif dk_have magisk; then DK_MANAGER=Magisk
    else DK_MANAGER=unknown
    fi
    return 0
}

dk_manager_name_raw() {
    if [ "$APATCH" = true ]; then
        echo APatch
    elif [ "$KSU_NEXT" = true ]; then
        echo "KernelSU Next"
    elif [ "$KSU" = true ]; then
        echo KernelSU
    elif [ -n "$MAGISK_VER_CODE" ]; then
        echo Magisk
    elif dk_have ksud; then
        echo KernelSU
    elif [ -f /data/adb/apd ]; then
        echo APatch
    elif dk_have magisk; then
        echo Magisk
    else
        echo unknown
    fi
}
