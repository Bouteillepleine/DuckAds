#!/system/bin/sh
_self=$(readlink -f "$0" 2>/dev/null || echo "$0")
MODDIR=${_self%/*}
case "$MODDIR" in
    ''|"$_self") MODDIR=/data/adb/modules/duckads ;;
esac
[ -f "$MODDIR/lib/common.sh" ] || MODDIR=/data/adb/modules/duckads

. "$MODDIR/lib/common.sh"
. "$MODDIR/lib/modes.sh"
. "$MODDIR/lib/engine.sh"
. "$MODDIR/lib/dns.sh"
. "$MODDIR/lib/exempt.sh"
. "$MODDIR/lib/sched.sh"
. "$MODDIR/lib/bench.sh"

case "$1" in
    --json) DK_JSON=1; shift ;;
esac

dk_seed
dk_load_conf
dk_mode_load

usage() {
    cat <<EOF
DuckAds $(sed -n 's/^version=//p' "$MODDIR/module.prop")

  duckads --update              fetch every enabled source and rebuild the hosts file
  duckads --reset               drop the blocklist, keep custom rules
  duckads --status              what is running right now
  duckads --enable | --disable  pause or resume blocking
  duckads --mode <name|auto>    force an injection mode ($DK_MODES)
  duckads --set <key> <value>   change a setting
  duckads --get [key]           print settings
  duckads --catalog             the curated list catalog
  duckads --source on|off|rm <id>
  duckads --source add <url> [label]
  duckads --sources             enabled sources and their last result
  duckads --block <domain>      add to blacklist.txt
  duckads --allow <domain>      add to whitelist.txt
  duckads --rules get|clear <blacklist|whitelist|custom|doh.local>
  duckads --exempt add|rm|list <package>
  duckads --dns on|off|status   DoH / DoT bypass blocking
  duckads --schedule off|daily|weekly|monthly|custom [expr]
  duckads --bench               measure what the hosts file costs a name lookup
  duckads --log                 tail the DuckAds log
EOF
}

hosts_live() {
    DK_LIVE_ROOT=0
    DK_LIVE_APP=-1
    grep -q DuckAds /system/etc/hosts 2>/dev/null && DK_LIVE_ROOT=1
    _t=""
    dk_have timeout && _t="timeout 5"
    if dk_have su; then
        _o=$($_t su 2000 -c "grep -c DuckAds /system/etc/hosts" 2>/dev/null)
        case "$_o" in
            ''|*[!0-9]*) DK_LIVE_APP=-1 ;;
            0) DK_LIVE_APP=0 ;;
            *) DK_LIVE_APP=1 ;;
        esac
    fi
    return 0
}

json_status() {
    dk_state_load
    dk_prop_load
    hosts_live
    dk_dns_status > /dev/null
    dk_exempt_mech_set
    dk_manager_name_set
    dk_mode_label_set "$DK_MODE"
    dk_sched_expr_set
    dk_private_dns_mode_set

    _susfs=""
    [ -x "$SUSFS_BIN" ] && _susfs=$("$SUSFS_BIN" show version 2>/dev/null | tr -d '\r\n')
    _size=$(stat -c %s "$DK_HOSTS" 2>/dev/null)
    case "$_size" in ''|*[!0-9]*) _size=0 ;; esac
    _exn=0
    while IFS= read -r _p; do
        [ -n "$_p" ] && _exn=$((_exn + 1))
    done < "$DATA/exempt.list" 2>/dev/null
    _srcn=0
    while IFS= read -r _l; do
        case "$_l" in on\|*) _srcn=$((_srcn + 1)) ;; esac
    done < "$DATA/sources.list" 2>/dev/null
    _nm=0
    dk_nomount_dir > /dev/null 2>&1 && _nm=1
    _crond=0
    dk_crond_running && _crond=1

    dk_esc "$DK_VERSION";        _v_version=$DK_E
    dk_esc "$DK_MODE";           _v_mode=$DK_E
    dk_esc "${mode:-auto}";      _v_modeset=$DK_E
    dk_esc "$DK_MODE_LABEL";     _v_modelabel=$DK_E
    dk_esc "$DK_MODE_AUTO";      _v_modeauto=$DK_E
    dk_esc "$DK_MODE_REASON";    _v_reason=$DK_E
    dk_esc "$DK_MANAGER";        _v_manager=$DK_E
    dk_esc "$DK_MANAGER_VER";    _v_managerver=$DK_E
    dk_esc "$_susfs";            _v_susfs=$DK_E
    dk_esc "$DKS_last_update";   _v_last=$DK_E
    dk_esc "$DK_HOSTS";          _v_path=$DK_E
    dk_esc "${update_schedule:-off}"; _v_sched=$DK_E
    dk_esc "$DK_SCHED_EXPR";     _v_schedx=$DK_E
    dk_esc "$DKS_doh_gate";      _v_gate=$DK_E
    dk_esc "$DK_PDNS";           _v_pdns=$DK_E
    dk_esc "$DKS_bench_when";    _v_bwhen=$DK_E
    dk_esc "$DK_MECH";           _v_mech=$DK_E
    dk_esc "$DK_MECH_LABEL";     _v_mechlabel=$DK_E
    dk_esc "$DKS_last_error";    _v_error=$DK_E

    dk_state_num blocked > /dev/null;        _n_blocked=$DK_N
    dk_state_num custom > /dev/null;         _n_custom=$DK_N
    dk_state_num sources_ok > /dev/null;     _n_ok=$DK_N
    dk_state_num sources_fail > /dev/null;   _n_fail=$DK_N
    dk_state_num build_seconds > /dev/null;  _n_build=$DK_N
    dk_state_num bench_entries > /dev/null;  _n_bent=$DK_N
    dk_state_num bench_scan_ms -1 > /dev/null;   _n_bscan=$DK_N
    dk_state_num bench_delta_cms -1 > /dev/null; _n_bdelta=$DK_N

    printf '{"version":"%s","versionCode":%s,"enabled":%s,"mode":"%s","mode_setting":"%s","mode_label":"%s","mode_auto":"%s","mode_reason":"%s","hidden":%s,"manager":"%s","susfs":"%s","nomount":%s,' \
        "$_v_version" "$DK_VCODE" "${enabled:-1}" "$_v_mode" "$_v_modeset" "$_v_modelabel" \
        "$_v_modeauto" "$_v_reason" "${DK_MODE_HIDDEN:-0}" "$_v_manager" "$_v_susfs" "$_nm"
    printf '"blocked":%s,"custom":%s,"sources_enabled":%s,"sources_ok":%s,"sources_fail":%s,"last_update":"%s","build_seconds":%s,"hosts_path":"%s","hosts_size":%s,"live_root":%s,"live_app":%s,' \
        "$_n_blocked" "$_n_custom" "$_srcn" "$_n_ok" "$_n_fail" "$_v_last" "$_n_build" \
        "$_v_path" "$_size" "${DK_LIVE_ROOT:-0}" "${DK_LIVE_APP:--1}"
    printf '"manager_ver":"%s",' "$_v_managerver"
    printf '"schedule":"%s","schedule_expr":"%s","crond":%s,' "$_v_sched" "$_v_schedx" "$_crond"
    printf '"doh":{"enabled":%s,"hooked":%s,"rules":%s,"strict":%s,"dot":%s,"gate":"%s","private_dns":"%s"},' \
        "${doh_block:-0}" "${DK_DNS_HOOKED:-0}" "${DK_DNS_RULES:-0}" "${doh_strict:-0}" "${doh_dot:-1}" \
        "$_v_gate" "$_v_pdns"
    printf '"bench":{"when":"%s","entries":%s,"scan_ms":%s,"delta_cms":%s},' \
        "$_v_bwhen" "$_n_bent" "$_n_bscan" "$_n_bdelta"
    printf '"exempt":{"mech":"%s","label":"%s","count":%s},' "$_v_mech" "$_v_mechlabel" "$_exn"
    printf '"settings":{'
    _first=1
    for k in $(dk_conf_keys); do
        eval "_val=\$$k"
        dk_esc "$_val"
        [ "$_first" = 1 ] || printf ','
        _first=0
        printf '"%s":"%s"' "$k" "$DK_E"
    done
    printf '},"error":"%s"}\n' "$_v_error"
}

json_catalog() {
    awk -f "$MODDIR/lib/catalog.awk" \
        -v SRCS="$DATA/sources.list" -v STAT="$DATA/sources.stat" \
        "$DATA/sources.list" "$DATA/sources.stat" "$MODDIR/data/catalog.tsv" 2>/dev/null
}

json_apps() {
    if [ "$1" = all ]; then
        pm list packages 2>/dev/null
    else
        pm list packages -3 2>/dev/null
    fi | LC_ALL=C sort | awk -f "$MODDIR/lib/apps.awk" -v EX="$DATA/exempt.list" 2>/dev/null
}

rules_file() {
    case "$1" in
        blacklist) echo "$DATA/blacklist.txt" ;;
        whitelist) echo "$DATA/whitelist.txt" ;;
        custom)    echo "$DATA/custom.txt" ;;
        doh.local) echo "$DATA/doh.local" ;;
        sources)   echo "$DATA/sources.list" ;;
        *)         return 1 ;;
    esac
}

source_id_from_url() {
    echo "$1" | sed 's|^https\{0,1\}://||; s|[^A-Za-z0-9]|-|g' | cut -c1-40
}

cmd_source() {
    case "$1" in
        add)
            _u=$(echo "$2" | base64 -d 2>/dev/null || echo "$2")
            _l=$(echo "$3" | base64 -d 2>/dev/null || echo "$3")
            case "$_u" in
                https://*|http://*) ;;
                *) dk_log "[x] not an http(s) url"; return 1 ;;
            esac
            case "$_u" in
                *[\`\$\;\&\|\<\>\'\"\ ]*) dk_log "[x] url has characters DuckAds will not pass to a shell"; return 1 ;;
            esac
            _id=$(source_id_from_url "$_u")
            [ -n "$_l" ] || _l=$_id
            case "$_l" in *[\|]*) _l=$_id ;; esac
            if grep -q "|$_id|" "$DATA/sources.list" 2>/dev/null; then
                dk_log "[!] already listed: $_id"
                return 0
            fi
            echo "on|block|$_id|$_u|$_l" >> "$DATA/sources.list"
            dk_log "[+] added $_id"
            ;;
        on|off)
            _id=$2
            _want=$1
            if grep -q "|$_id|" "$DATA/sources.list" 2>/dev/null; then
                awk -F'|' -v i="$_id" -v w="$_want" 'BEGIN { OFS = "|" }
                    $3 == i { $1 = w } { print }' "$DATA/sources.list" > "$DATA/sources.tmp" &&
                    mv -f "$DATA/sources.tmp" "$DATA/sources.list"
            else
                _line=$(awk -F'\t' -v i="$_id" -v w="$_want" '$1 == i { print w "|" $2 "|" $1 "|" $6 "|" $4 }' "$MODDIR/data/catalog.tsv")
                [ -n "$_line" ] || { dk_log "[x] no such list: $_id"; return 1; }
                echo "$_line" >> "$DATA/sources.list"
            fi
            chmod 0600 "$DATA/sources.list" 2>/dev/null
            dk_log "[+] $_id $_want"
            ;;
        rm)
            _id=$2
            grep -v "|$_id|" "$DATA/sources.list" > "$DATA/sources.tmp" 2>/dev/null &&
                mv -f "$DATA/sources.tmp" "$DATA/sources.list"
            dk_log "[+] removed $_id"
            ;;
        *)
            usage
            return 1
            ;;
    esac
}

cmd_rules() {
    _f=$(rules_file "$2") || { dk_log "[x] no such rule file: $2"; return 1; }
    case "$1" in
        get)   cat "$_f" 2>/dev/null ;;
        clear) : > "$_f"; dk_log "[+] cleared $2" ;;
        put)
            _tmp=$(dk_tmpdir)/duckads.rule.$$
            echo "$3" | base64 -d > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; dk_log "[x] bad payload"; return 1; }
            sed -i 's/\r$//' "$_tmp"
            mv -f "$_tmp" "$_f"
            chmod 0600 "$_f" 2>/dev/null
            dk_log "[+] wrote $2"
            ;;
        add)
            _v=$(echo "$3" | base64 -d 2>/dev/null || echo "$3")
            [ -n "$_v" ] || return 1
            grep -qxF "$_v" "$_f" 2>/dev/null || echo "$_v" >> "$_f"
            dk_log "[+] $2 += $_v"
            ;;
        del)
            _v=$(echo "$3" | base64 -d 2>/dev/null || echo "$3")
            grep -vxF "$_v" "$_f" > "$_f.tmp" 2>/dev/null
            mv -f "$_f.tmp" "$_f"
            dk_log "[+] $2 -= $_v"
            ;;
        *) usage; return 1 ;;
    esac
}

cmd_update() {
    dk_lock_acquire || return 1
    trap 'dk_lock_release' EXIT
    if [ "$2" = --cron ] || [ "$1" = --cron ]; then
        if [ "$wifi_only" = 1 ] && ! dk_on_wifi; then
            dk_log "[*] scheduled run skipped, not on Wi-Fi"
            dk_lock_release
            return 0
        fi
    fi
    dk_build
    _rc=$?
    dk_lock_release
    return $_rc
}

case "$1" in
    ''|--status|-s)
        if [ "$DK_JSON" = 1 ]; then
            json_status
        else
            echo "DuckAds $(sed -n 's/^version=//p' "$MODDIR/module.prop")"
            echo "  mode      : $DK_MODE ($(dk_mode_label "$DK_MODE"))"
            echo "  reason    : $DK_MODE_REASON"
            echo "  manager   : $(dk_manager_name)"
            echo "  blocked   : $(dk_state_get blocked)"
            echo "  custom    : $(dk_state_get custom)"
            echo "  sources   : $(dk_state_get sources_ok) ok, $(dk_state_get sources_fail) failed"
            echo "  updated   : $(dk_state_get last_update)"
            echo "  schedule  : ${update_schedule} $(dk_sched_expr)"
            echo "  dns block : $(dk_dns_status)"
            echo "  exempt    : $(dk_exempt_mech_label "$(dk_exempt_mech)")"
            hosts_live
            echo "  live      : root=$DK_LIVE_ROOT app=$DK_LIVE_APP"
        fi
        ;;
    --update|-u)
        cmd_update "$@"
        ;;
    --reset)
        dk_lock_acquire || exit 1
        dk_reset_hosts
        dk_lock_release
        ;;
    --enable)
        dk_cfg_set enabled 1
        enabled=1
        dk_describe
        dk_log "[+] blocking enabled, reboot or run --update to rebuild"
        ;;
    --disable)
        dk_cfg_set enabled 0
        enabled=0
        dk_lock_acquire || exit 1
        dk_reset_hosts
        dk_lock_release
        ;;
    --mode)
        if [ "$2" = auto ] || dk_mode_valid "$2"; then
            dk_cfg_set mode "$2"
            mode=$2
            dk_log "[+] mode set to $2 - reboot to apply"
        else
            dk_log "[x] modes: auto $DK_MODES"
            exit 1
        fi
        ;;
    --set)
        dk_cfg_set "$2" "$3" || exit 1
        dk_load_conf
        case "$2" in
            update_schedule|update_cron|update_hour) dk_sched_apply ;;
            doh_block|doh_strict|doh_dot) dk_dns_apply ;;
        esac
        dk_log "[+] $2=$3"
        ;;
    --get)
        if [ -n "$2" ]; then
            case " $(dk_conf_keys) " in
                *" $2 "*) eval "printf '%s\n' \"\$$2\"" ;;
                *) dk_log "[x] unknown setting: $2"; exit 1 ;;
            esac
        else
            for k in $(dk_conf_keys); do eval "echo \"$k=\$$k\""; done
        fi
        ;;
    --catalog)
        json_catalog
        ;;
    --sources)
        if [ "$DK_JSON" = 1 ]; then
            json_catalog
        else
            dk_sources_enabled
        fi
        ;;
    --source)
        shift
        cmd_source "$@"
        ;;
    --block)
        cmd_rules add blacklist "$2"
        ;;
    --allow)
        cmd_rules add whitelist "$2"
        ;;
    --rules)
        shift
        cmd_rules "$@"
        ;;
    --apps)
        json_apps "$2"
        ;;
    --exempt)
        case "$2" in
            add)  dk_exempt_set "$3" 1 ;;
            rm)   dk_exempt_set "$3" 0 ;;
            list) dk_exempt_list ;;
            *)    usage; exit 1 ;;
        esac
        ;;
    --dns)
        case "$2" in
            on)     dk_cfg_set doh_block 1; doh_block=1; dk_dns_apply ;;
            off)    dk_cfg_set doh_block 0; doh_block=0; dk_dns_clear ;;
            status) dk_dns_status ;;
            *)      usage; exit 1 ;;
        esac
        ;;
    --private-dns-off)
        dk_private_dns_off && dk_log "[+] private DNS set to off"
        ;;
    --schedule)
        case "$2" in
            off|daily|weekly|monthly)
                dk_cfg_set update_schedule "$2"
                update_schedule=$2
                dk_sched_apply && dk_log "[+] schedule: $2"
                ;;
            custom)
                _e=$(echo "$3" | base64 -d 2>/dev/null || echo "$3")
                dk_cron_valid "$_e" || { dk_log "[x] invalid cron expression"; exit 1; }
                dk_cfg_set update_cron "$_e"
                dk_cfg_set update_schedule custom
                update_cron=$_e
                update_schedule=custom
                dk_sched_apply && dk_log "[+] schedule: $_e"
                ;;
            *) usage; exit 1 ;;
        esac
        ;;
    --bench)
        dk_bench
        ;;
    --log)
        tail -n "${2:-200}" "$LOGFILE" 2>/dev/null
        ;;
    --describe)
        dk_describe
        ;;
    -h|--help)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
