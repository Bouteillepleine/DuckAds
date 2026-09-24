dk_now_ms() {
    _n=$(date +%s%N 2>/dev/null)
    case "$_n" in
        ''|*[!0-9]*) echo "" ; return 1 ;;
    esac
    echo $((_n / 1000000))
}

dk_bench_file() {
    _f=$1
    [ -r "$_f" ] || return 1
    cat "$_f" > /dev/null 2>&1
    _b0=$(dk_now_ms) || return 1
    awk 'END { }' /dev/null > /dev/null 2>&1
    _b1=$(dk_now_ms) || return 1
    _base=$((_b1 - _b0))
    _t0=$(dk_now_ms) || return 1
    awk 'END { }' "$_f" > /dev/null 2>&1
    _t1=$(dk_now_ms) || return 1
    _ms=$(((_t1 - _t0) - _base))
    [ "$_ms" -lt 0 ] && _ms=0
    echo "$_ms"
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

dk_bench_lookup() {
    _name=$1
    _runs=${2:-8}
    dk_have ping || return 1
    _t0=$(dk_now_ms) || return 1
    _i=0
    while [ "$_i" -lt "$_runs" ]; do
        ping -c 1 -w 1 "$_name" > /dev/null 2>&1
        _i=$((_i + 1))
    done
    _t1=$(dk_now_ms) || return 1
    echo $(((_t1 - _t0) * 100 / _runs))
}

dk_bench() {
    _f=$DK_HOSTS
    [ -r "$_f" ] || { dk_log "[x] no hosts file to measure yet"; return 1; }

    _bytes=$(stat -c %s "$_f" 2>/dev/null || echo 0)
    _lines=$(wc -l < "$_f" 2>/dev/null)
    case "$_lines" in ''|*[!0-9]*) _lines=0 ;; esac

    _scan=$(dk_bench_file "$_f")
    case "$_scan" in ''|*[!0-9]*) _scan=-1 ;; esac

    _first=$(grep -m1 "^$sink " "$_f" 2>/dev/null | awk '{ print $2 }')
    _last=$(grep "^$sink " "$_f" 2>/dev/null | tail -n1 | awk '{ print $2 }')

    _top=-1
    _bottom=-1
    _delta=-1
    if [ -n "$_first" ] && [ -n "$_last" ] && [ "$_first" != "$_last" ]; then
        _a=$(dk_bench_lookup "$_first")
        _b=$(dk_bench_lookup "$_last")
        if dk_is_num "$_a" && dk_is_num "$_b"; then
            _top=$_a
            _bottom=$_b
            _delta=$((_bottom - _top))
            [ "$_delta" -lt 0 ] && _delta=0
        fi
    fi

    dk_state_set bench_entries "$_lines"
    dk_state_set bench_bytes "$_bytes"
    dk_state_set bench_scan_ms "$_scan"
    dk_state_set bench_top_cms "$_top"
    dk_state_set bench_bottom_cms "$_bottom"
    dk_state_set bench_delta_cms "$_delta"
    dk_state_set bench_when "$(date '+%Y-%m-%d %H:%M')"

    if [ "$DK_JSON" = 1 ]; then
        printf '{"entries":%s,"bytes":%s,"scan_ms":%s,"top_cms":%s,"bottom_cms":%s,"delta_cms":%s,"verdict":"%s"}\n' \
            "$_lines" "$_bytes" "$_scan" "$_top" "$_bottom" "$_delta" "$(dk_json_str "$(dk_bench_verdict "$_delta" "$_lines")")"
        return 0
    fi

    dk_log "[+] hosts file: $_lines lines, $((_bytes / 1024)) KB"
    [ "$_scan" -ge 0 ] && dk_log "    one full pass over the file: ${_scan} ms"
    if [ "$_delta" -ge 0 ]; then
        dk_log "    lookup of the first blocked name: $(dk_fmt_cms "$_top") ms"
        dk_log "    lookup of the last blocked name:  $(dk_fmt_cms "$_bottom") ms"
        dk_log "    cost of the list length:          $(dk_fmt_cms "$_delta") ms per lookup"
    else
        dk_log "    end-to-end lookup timing needs ping and a built hosts file"
    fi
    dk_log "    $(dk_bench_verdict "$_delta" "$_lines")"
    return 0
}

dk_bench_verdict() {
    _d=$1
    _n=$2
    if [ "$_d" -lt 0 ] 2>/dev/null; then
        if [ "$_n" -gt 250000 ]; then
            echo "$_n lines is a lot - if name lookups feel slow, drop a tier or cap the entries"
            return 0
        fi
        echo "nothing measured end to end, but $_n lines is a normal size"
        return 0
    fi
    if [ "$_d" -lt 100 ]; then
        echo "under a millisecond per lookup - the list length costs you nothing"
    elif [ "$_d" -lt 300 ]; then
        echo "a few milliseconds per lookup - fine in practice"
    elif [ "$_d" -lt 1000 ]; then
        echo "noticeable on pages with many domains - consider a smaller tier or an entry cap"
    else
        echo "this list is slowing lookups down - drop an aggressive tier or set an entry cap"
    fi
}
