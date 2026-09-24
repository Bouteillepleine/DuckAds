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
  duckads --log                 tail the DuckAds log
EOF
}

hosts_live() {
    _root=0
    _app=-1
    grep -q DuckAds /system/etc/hosts 2>/dev/null && _root=1
    _t=""
    dk_have timeout && _t="timeout 5"
    if dk_have su; then
        if $_t su 2000 -c "grep -q DuckAds /system/etc/hosts" > /dev/null 2>&1; then
            _app=1
        else
            $_t su 2000 -c "head -c 1 /system/etc/hosts" > /dev/null 2>&1 && _app=0
        fi
    fi
    echo "$_root|$_app"
}

json_status() {
    _live=$(hosts_live)
    _dns=$(dk_dns_status)
    _mech=$(dk_exempt_mech)
    _susfs=""
    [ -x "$SUSFS_BIN" ] && _susfs=$("$SUSFS_BIN" show version 2>/dev/null | tr -d '\r\n')
    _size=$(stat -c %s "$DK_HOSTS" 2>/dev/null || echo 0)
    _exn=$(dk_exempt_list | grep -c .)
    _srcn=$(dk_sources_enabled | grep -c .)
    printf '{'
    printf '"version":"%s",' "$(dk_json_str "$(sed -n 's/^version=//p' "$MODDIR/module.prop")")"
    printf '"versionCode":%s,' "$(dk_versioncode)"
    printf '"enabled":%s,' "${enabled:-1}"
    printf '"mode":"%s",' "$(dk_json_str "$DK_MODE")"
    printf '"mode_setting":"%s",' "$(dk_json_str "${mode:-auto}")"
    printf '"mode_label":"%s",' "$(dk_json_str "$(dk_mode_label "$DK_MODE")")"
    printf '"mode_auto":"%s",' "$(dk_json_str "$DK_MODE_AUTO")"
    printf '"mode_reason":"%s",' "$(dk_json_str "$DK_MODE_REASON")"
    printf '"hidden":%s,' "$(dk_mode_hidden "$DK_MODE")"
    printf '"manager":"%s",' "$(dk_json_str "$(dk_manager_name)")"
    printf '"susfs":"%s",' "$(dk_json_str "$_susfs")"
    printf '"nomount":%s,' "$(dk_nomount_dir > /dev/null 2>&1 && echo 1 || echo 0)"
    printf '"blocked":%s,' "$(dk_state_get blocked | grep -E '^[0-9]+$' || echo 0)"
    printf '"custom":%s,' "$(dk_state_get custom | grep -E '^[0-9]+$' || echo 0)"
    printf '"sources_enabled":%s,' "${_srcn:-0}"
    printf '"sources_ok":%s,' "$(dk_state_get sources_ok | grep -E '^[0-9]+$' || echo 0)"
    printf '"sources_fail":%s,' "$(dk_state_get sources_fail | grep -E '^[0-9]+$' || echo 0)"
    printf '"last_update":"%s",' "$(dk_json_str "$(dk_state_get last_update)")"
    printf '"build_seconds":%s,' "$(dk_state_get build_seconds | grep -E '^[0-9]+$' || echo 0)"
    printf '"hosts_path":"%s",' "$(dk_json_str "$DK_HOSTS")"
    printf '"hosts_size":%s,' "${_size:-0}"
    printf '"live_root":%s,' "${_live%%|*}"
    printf '"live_app":%s,' "${_live##*|}"
    printf '"schedule":"%s",' "$(dk_json_str "${update_schedule:-off}")"
    printf '"schedule_expr":"%s",' "$(dk_json_str "$(dk_sched_expr)")"
    printf '"crond":%s,' "$(dk_crond_running && echo 1 || echo 0)"
    printf '"doh":{"enabled":%s,"hooked":%s,"rules":%s,"strict":%s,"dot":%s,"private_dns":"%s"},' \
        "${doh_block:-0}" "${_dns%%|*}" "${_dns##*|}" "${doh_strict:-0}" "${doh_dot:-1}" \
        "$(dk_json_str "$(dk_private_dns_mode)")"
    printf '"exempt":{"mech":"%s","label":"%s","count":%s},' \
        "$(dk_json_str "$_mech")" "$(dk_json_str "$(dk_exempt_mech_label "$_mech")")" "${_exn:-0}"
    printf '"settings":{'
    _first=1
    for k in $(dk_conf_keys); do
        eval "_v=\$$k"
        [ "$_first" = 1 ] || printf ','
        _first=0
        printf '"%s":"%s"' "$k" "$(dk_json_str "$_v")"
    done
    printf '},'
    printf '"error":"%s"' "$(dk_json_str "$(dk_state_get last_error)")"
    printf '}\n'
}

json_catalog() {
    _first=1
    printf '['
    while IFS='	' read -r id kind cat name def url note; do
        [ -n "$id" ] || continue
        case "$id" in \#*) continue ;; esac
        _state=off
        grep -q "^on|[^|]*|$id|" "$DATA/sources.list" 2>/dev/null && _state=on
        _cnt=$(awk -F'|' -v i="$id" '$1 == i { print $2 }' "$DATA/sources.stat" 2>/dev/null | head -n1)
        _st=$(awk -F'|' -v i="$id" '$1 == i { print $3 }' "$DATA/sources.stat" 2>/dev/null | head -n1)
        case "$_cnt" in ''|*[!0-9]*) _cnt=0 ;; esac
        [ "$_first" = 1 ] || printf ','
        _first=0
        printf '{"id":"%s","kind":"%s","cat":"%s","name":"%s","url":"%s","note":"%s","state":"%s","count":%s,"result":"%s"}' \
            "$(dk_json_str "$id")" "$(dk_json_str "$kind")" "$(dk_json_str "$cat")" \
            "$(dk_json_str "$name")" "$(dk_json_str "$url")" "$(dk_json_str "$note")" \
            "$_state" "$_cnt" "$(dk_json_str "$_st")"
    done < "$MODDIR/data/catalog.tsv"
    while IFS='|' read -r state kind id url name; do
        [ -n "$id" ] || continue
        awk -F'\t' -v i="$id" '$1 == i { found = 1 } END { exit !found }' "$MODDIR/data/catalog.tsv" && continue
        _cnt=$(awk -F'|' -v i="$id" '$1 == i { print $2 }' "$DATA/sources.stat" 2>/dev/null | head -n1)
        _st=$(awk -F'|' -v i="$id" '$1 == i { print $3 }' "$DATA/sources.stat" 2>/dev/null | head -n1)
        case "$_cnt" in ''|*[!0-9]*) _cnt=0 ;; esac
        [ "$_first" = 1 ] || printf ','
        _first=0
        printf '{"id":"%s","kind":"%s","cat":"custom","name":"%s","url":"%s","note":"","state":"%s","count":%s,"result":"%s"}' \
            "$(dk_json_str "$id")" "$(dk_json_str "$kind")" "$(dk_json_str "$name")" \
            "$(dk_json_str "$url")" "$state" "$_cnt" "$(dk_json_str "$_st")"
    done < "$DATA/sources.list"
    printf ']\n'
}

json_apps() {
    _scope=$1
    _list=$(pm list packages -3 2>/dev/null)
    [ "$_scope" = all ] && _list=$(pm list packages 2>/dev/null)
    _first=1
    printf '['
    for p in $(echo "$_list" | sed 's/^package://' | sort); do
        dk_pkg_valid "$p" || continue
        _ex=0
        grep -q "^$p\$" "$DATA/exempt.list" 2>/dev/null && _ex=1
        [ "$_first" = 1 ] || printf ','
        _first=0
        printf '{"pkg":"%s","exempt":%s}' "$(dk_json_str "$p")" "$_ex"
    done
    printf ']\n'
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
            _l=$(hosts_live)
            echo "  live      : root=${_l%%|*} app=${_l##*|}"
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
