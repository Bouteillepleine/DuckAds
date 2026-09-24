DK_UA="DuckAds/$(dk_versioncode 2>/dev/null) (Android; systemless hosts)"

dk_dl_setup() {
    if dk_have curl; then
        DK_DL=curl
    elif busybox wget --help > /dev/null 2>&1; then
        DK_DL=wget
    else
        DK_DL=none
    fi
}

dk_fetch() {
    _url=$1
    _out=$2
    case "$_url" in
        https://*|http://*) ;;
        *) return 2 ;;
    esac
    case "$DK_DL" in
        curl)
            curl -sL --fail --connect-timeout 10 --max-time 180 -A "$DK_UA" -o "$_out" "$_url" 2>/dev/null
            ;;
        wget)
            busybox wget -T 20 --no-check-certificate -U "$DK_UA" -qO "$_out" "$_url" 2>/dev/null
            ;;
        *)
            return 3
            ;;
    esac
}

dk_on_wifi() {
    if dk_have dumpsys; then
        dumpsys connectivity 2>/dev/null | grep -m1 -q "TRANSPORT_WIFI" && return 0
        dumpsys connectivity 2>/dev/null | grep -m1 -q "TRANSPORT_CELLULAR" && return 1
    fi
    ip route 2>/dev/null | grep -q "^default.*dev wlan" && return 0
    return 1
}

dk_sources_enabled() {
    [ -f "$DATA/sources.list" ] || return 0
    grep -v "^#" "$DATA/sources.list" 2>/dev/null | grep "^on|"
}

dk_source_field() {
    echo "$1" | cut -d'|' -f"$2"
}

dk_build() {
    dk_dl_setup
    if [ "$DK_DL" = none ]; then
        dk_log "[x] neither curl nor busybox wget is available"
        return 1
    fi

    _t0=$(date +%s)
    TMP=$(dk_tmpdir)/duckads.$$
    rm -rf "$TMP" 2>/dev/null
    mkdir -p "$TMP/raw" "$TMP/p" || { dk_log "[x] no writable temp dir"; return 1; }

    : > "$TMP/allow.abp"
    : > "$TMP/allow.remote"
    : > "$TMP/cand"
    : > "$TMP/srcstat"
    : > "$TMP/okmark"
    : > "$TMP/failmark"

    _ok=0
    _fail=0
    _n=0

    dk_sources_enabled | while IFS= read -r line; do
        _n=$((_n + 1))
        kind=$(dk_source_field "$line" 2)
        id=$(dk_source_field "$line" 3)
        url=$(dk_source_field "$line" 4)
        [ -n "$url" ] || continue
        dk_log "[>] $id"
        if dk_fetch "$url" "$TMP/raw/$_n" && [ -s "$TMP/raw/$_n" ]; then
            if [ "$kind" = allow ]; then
                awk -f "$MODDIR/lib/parse.awk" -v ALLOWMODE=1 "$TMP/raw/$_n" >> "$TMP/allow.remote" 2>/dev/null
                echo "$id|allow|ok" >> "$TMP/srcstat"
            else
                awk -f "$MODDIR/lib/parse.awk" -v ALLOW="$TMP/allow.abp" "$TMP/raw/$_n" > "$TMP/p/$_n" 2>/dev/null
                _c=$(wc -l < "$TMP/p/$_n" 2>/dev/null)
                case "$_c" in ''|*[!0-9]*) _c=0 ;; esac
                cat "$TMP/p/$_n" >> "$TMP/cand"
                rm -f "$TMP/p/$_n" 2>/dev/null
                echo "$id|$_c|ok" >> "$TMP/srcstat"
                dk_log "    $_c domains"
            fi
            echo ok >> "$TMP/okmark"
        else
            dk_log "[x] failed: $id"
            echo "$id|0|fail" >> "$TMP/srcstat"
            echo fail >> "$TMP/failmark"
        fi
        rm -f "$TMP/raw/$_n" 2>/dev/null
    done

    _ok=$(wc -l < "$TMP/okmark" 2>/dev/null)
    _fail=$(wc -l < "$TMP/failmark" 2>/dev/null)
    case "$_ok" in ''|*[!0-9]*) _ok=0 ;; esac
    case "$_fail" in ''|*[!0-9]*) _fail=0 ;; esac

    if [ "$_ok" = 0 ] && [ "$_fail" -gt 0 ]; then
        dk_log "[x] every source failed - keeping the current hosts file"
        rm -rf "$TMP"
        dk_state_set last_error "all sources failed"
        return 1
    fi

    awk -f "$MODDIR/lib/parse.awk" -v ALLOW="" "$DATA/blacklist.txt" >> "$TMP/cand" 2>/dev/null

    if [ ! -s "$TMP/cand" ]; then
        dk_log "[x] no domains parsed - keeping the current hosts file"
        rm -rf "$TMP"
        dk_state_set last_error "no domains parsed"
        return 1
    fi

    {
        cat "$DATA/whitelist.txt" 2>/dev/null
        cat "$TMP/allow.abp" 2>/dev/null
        cat "$TMP/allow.remote" 2>/dev/null
    } > "$TMP/wl"

    LC_ALL=C sort -u "$TMP/cand" > "$TMP/cand.s"
    awk -f "$MODDIR/lib/filter.awk" -v WL="$TMP/wl" "$TMP/cand.s" > "$TMP/kept"

    if [ "$compact" = 1 ]; then
        awk '{n=split($0,a,"."); k=""; for(i=n;i>0;i--) k=k a[i] "."; print k "\t" $0}' "$TMP/kept" |
            LC_ALL=C sort |
            awk -F'\t' 'last != "" && index($1, last) == 1 { next } { last = $1; print $2 }' > "$TMP/final"
    else
        cp "$TMP/kept" "$TMP/final"
    fi

    case "$max_entries" in
        ''|0|*[!0-9]*) ;;
        *) head -n "$max_entries" "$TMP/final" > "$TMP/final.cut" && mv -f "$TMP/final.cut" "$TMP/final" ;;
    esac

    _blocked=$(wc -l < "$TMP/final" 2>/dev/null)
    case "$_blocked" in ''|*[!0-9]*) _blocked=0 ;; esac
    if [ "$_blocked" = 0 ]; then
        dk_log "[x] filtering left nothing to block - keeping the current hosts file"
        rm -rf "$TMP"
        dk_state_set last_error "empty result after filtering"
        return 1
    fi

    dk_compose "$TMP/final" "$TMP/hosts.new" || { rm -rf "$TMP"; return 1; }
    dk_install_hosts "$TMP/hosts.new" || { rm -rf "$TMP"; return 1; }

    cp -f "$TMP/srcstat" "$DATA/sources.stat" 2>/dev/null
    chmod 0600 "$DATA/sources.stat" 2>/dev/null

    _custom=$(grep -cvE '^[[:space:]]*($|#)' "$DATA/custom.txt" 2>/dev/null)
    case "$_custom" in ''|*[!0-9]*) _custom=0 ;; esac
    _t1=$(date +%s)
    _dur=$((_t1 - _t0))

    dk_state_set blocked "$_blocked"
    dk_state_set custom "$_custom"
    dk_state_set sources_ok "$_ok"
    dk_state_set sources_fail "$_fail"
    dk_state_set last_update "$(date '+%Y-%m-%d %H:%M')"
    dk_state_set last_update_epoch "$_t1"
    dk_state_set build_seconds "$_dur"
    dk_state_set last_error ""

    rm -rf "$TMP"
    dk_log "[+] blocked: $_blocked | custom: $_custom | sources: $_ok ok, $_fail failed | ${_dur}s"
    dk_describe
    return 0
}

dk_compose() {
    _domains=$1
    _out=$2
    {
        echo "127.0.0.1 localhost"
        echo "::1 localhost"
        echo "127.0.0.1 localhost.localdomain"
        dk_orig_lines
        grep -vE '^[[:space:]]*($|#)' "$DATA/custom.txt" 2>/dev/null | sed 's/\r$//'
    } > "$_out"

    if [ "$ipv6_sink" = 1 ]; then
        awk -v s="$sink" '{ print s " " $0; print ":: " $0 }' "$_domains" >> "$_out"
    else
        awk -v s="$sink" '{ print s " " $0 }' "$_domains" >> "$_out"
    fi

    echo "# DuckAds v$(dk_versioncode) built $(date '+%Y-%m-%d %H:%M') entries $(wc -l < "$_domains")" >> "$_out"

    grep -q "^127.0.0.1 localhost" "$_out" || {
        dk_log "[x] generated hosts file failed its sanity check"
        return 1
    }
    return 0
}

dk_install_hosts() {
    _new=$1
    mkdir -p "${DK_HOSTS%/*}"
    [ -f "$DK_HOSTS" ] && cp -f "$DK_HOSTS" "$DATA/hosts.bak" 2>/dev/null
    if ! cat "$_new" > "$DK_HOSTS" 2>/dev/null; then
        dk_log "[x] could not write $DK_HOSTS"
        [ -f "$DATA/hosts.bak" ] && cat "$DATA/hosts.bak" > "$DK_HOSTS" 2>/dev/null
        return 1
    fi
    dk_set_perm "$DK_HOSTS"
    dk_publish
    dk_susfs_refresh
    dk_nomount_reload
    return 0
}

dk_reset_hosts() {
    mkdir -p "${DK_HOSTS%/*}"
    TMP=$(dk_tmpdir)/duckads.reset.$$
    {
        echo "127.0.0.1 localhost"
        echo "::1 localhost"
        echo "127.0.0.1 localhost.localdomain"
        dk_orig_lines
        grep -vE '^[[:space:]]*($|#)' "$DATA/custom.txt" 2>/dev/null
        echo "# DuckAds v$(dk_versioncode) reset $(date '+%Y-%m-%d %H:%M')"
    } > "$TMP"
    dk_install_hosts "$TMP"
    _rc=$?
    rm -f "$TMP"
    dk_state_set blocked 0
    dk_state_set last_update "$(date '+%Y-%m-%d %H:%M')"
    dk_describe
    return $_rc
}

dk_describe() {
    [ "$notify" = 1 ] || return 0
    _b=$(dk_state_get blocked)
    _c=$(dk_state_get custom)
    _f=$(dk_state_get sources_fail)
    [ -n "$_b" ] || _b=0
    [ -n "$_c" ] || _c=0
    _label=$(dk_mode_label "${DK_MODE:-$(dk_state_get mode_active)}")
    if [ "$enabled" = 0 ]; then
        _s="description=status: paused ⏸ | $_label"
    elif [ "$_b" = 0 ]; then
        _s="description=status: ready 🚀 | $_label"
    else
        _s="description=status: active ✅ | blocked: $_b 🚫 | custom: $_c 🤖 | $_label 🦆"
        [ -n "$_f" ] && [ "$_f" != 0 ] && _s="$_s | $_f source(s) failed"
    fi
    grep -qxF "$_s" "$MODDIR/module.prop" 2>/dev/null && return 0
    awk -v d="$_s" '/^description=/ { print d; next } { print }' \
        "$MODDIR/module.prop" > "$MODDIR/module.prop.tmp" 2>/dev/null &&
        mv -f "$MODDIR/module.prop.tmp" "$MODDIR/module.prop" 2>/dev/null
    rm -f "$MODDIR/module.prop.tmp" 2>/dev/null
}
