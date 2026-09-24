dk_now_us() {
    _n=$(date +%s%N 2>/dev/null)
    case "$_n" in
        ''|*[!0-9]*) echo "" ; return 1 ;;
    esac
    echo $((_n / 1000))
}

dk_is_num() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

dk_fmt_cms() {
    _v=$1
    _w=$((_v / 100))
    _fr=$((_v % 100))
    [ "$_fr" -lt 10 ] && _fr="0$_fr"
    echo "$_w.$_fr"
}

dk_bench_scan() {
    _f=$1
    [ -r "$_f" ] || return 1
    cat "$_f" > /dev/null 2>&1
    _b0=$(dk_now_us) || return 1
    awk 'END { }' /dev/null > /dev/null 2>&1
    _b1=$(dk_now_us) || return 1
    _base=$((_b1 - _b0))
    _t0=$(dk_now_us) || return 1
    awk 'END { }' "$_f" > /dev/null 2>&1
    _t1=$(dk_now_us) || return 1
    _ms=$(((_t1 - _t0 - _base) / 1000))
    [ "$_ms" -lt 0 ] && _ms=0
    echo "$_ms"
}

dk_bench_lookup() {
    _name=$1
    _runs=${2:-12}
    dk_have ping || return 1
    ping -c 1 -w 1 "$_name" > /dev/null 2>&1
    _min=-1
    _i=0
    while [ "$_i" -lt "$_runs" ]; do
        _a=$(dk_now_us) || return 1
        ping -c 1 -w 1 "$_name" > /dev/null 2>&1
        _b=$(dk_now_us) || return 1
        _d=$((_b - _a))
        if [ "$_min" -lt 0 ] || [ "$_d" -lt "$_min" ]; then
            _min=$_d
        fi
        _i=$((_i + 1))
    done
    [ "$_min" -lt 0 ] && return 1
    echo $((_min / 10))
}

dk_bench() {
    _f=$DK_HOSTS
    [ -r "$_f" ] || { dk_log "[x] no hosts file to measure yet"; return 1; }

    _bytes=$(stat -c %s "$_f" 2>/dev/null || echo 0)
    _lines=$(wc -l < "$_f" 2>/dev/null)
    case "$_lines" in ''|*[!0-9]*) _lines=0 ;; esac

    _scan=$(dk_bench_scan "$_f")
    case "$_scan" in ''|*[!0-9]*) _scan=-1 ;; esac

    _first=$(grep -m1 "^$sink " "$_f" 2>/dev/null | awk '{ print $2 }')
    _last=$(grep "^$sink " "$_f" 2>/dev/null | tail -n1 | awk '{ print $2 }')

    _top=-1
    _bottom=-1
    _delta=-1
    _floor=-1
    if [ -n "$_first" ] && [ -n "$_last" ] && [ "$_first" != "$_last" ]; then
        _a=$(dk_bench_lookup "$_first")
        _b=$(dk_bench_lookup "$_last")
        _c=$(dk_bench_lookup "$_first")
        if dk_is_num "$_a" && dk_is_num "$_b" && dk_is_num "$_c"; then
            _top=$_a
            _bottom=$_b
            _floor=$((_a - _c))
            [ "$_floor" -lt 0 ] && _floor=$((_c - _a))
            _delta=$((_bottom - _top))
            [ "$_delta" -lt 0 ] && _delta=0
        fi
    fi

    dk_state_set bench_entries "$_lines"
    dk_state_set bench_bytes "$_bytes"
    dk_state_set bench_scan_ms "$_scan"
    dk_state_set bench_top_cms "$_top"
    dk_state_set bench_delta_cms "$_delta"
    dk_state_set bench_floor_cms "$_floor"
    dk_state_set bench_when "$(date '+%Y-%m-%d %H:%M')"

    _verdict=$(dk_bench_verdict "$_delta" "$_floor" "$_lines")

    if [ "$DK_JSON" = 1 ]; then
        printf '{"entries":%s,"bytes":%s,"scan_ms":%s,"top_cms":%s,"delta_cms":%s,"floor_cms":%s,"verdict":"%s"}\n' \
            "$_lines" "$_bytes" "$_scan" "$_top" "$_delta" "$_floor" "$(dk_json_str "$_verdict")"
        return 0
    fi

    dk_log "[+] hosts file: $_lines lines, $((_bytes / 1024)) KB"
    [ "$_scan" -ge 0 ] && dk_log "    reading and splitting the whole file: ${_scan} ms (upper bound - the resolver's C parser is faster than awk)"
    if [ "$_delta" -ge 0 ]; then
        dk_log "    a blocked name resolves in: $(dk_fmt_cms "$_top") ms, most of which is starting the probe"
        dk_log "    first entry vs last entry:  $(dk_fmt_cms "$_delta") ms"
        dk_log "    noise floor of this probe:  $(dk_fmt_cms "$_floor") ms"
    fi
    dk_log "    $_verdict"
    return 0
}

dk_bench_verdict() {
    _d=$1
    _fl=$2
    _n=$3
    if [ "$_d" -lt 0 ] 2>/dev/null || [ "$_fl" -lt 0 ] 2>/dev/null; then
        echo "no end-to-end timing available, and $_n entries is a normal size"
        return 0
    fi
    if [ "$_d" -le "$_fl" ]; then
        echo "the list length costs less than this probe can resolve (under $(dk_fmt_cms "$_fl") ms) - nothing to worry about at $_n entries"
        return 0
    fi
    if [ "$_d" -lt 300 ]; then
        echo "about $(dk_fmt_cms "$_d") ms per lookup above the noise - fine in practice"
    elif [ "$_d" -lt 1000 ]; then
        echo "about $(dk_fmt_cms "$_d") ms per lookup - noticeable on pages with many domains"
    else
        echo "about $(dk_fmt_cms "$_d") ms per lookup - consider a smaller tier or an entry cap"
    fi
}
