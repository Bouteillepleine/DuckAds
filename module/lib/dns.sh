DK_CHAIN_T=duckads_t
DK_CHAIN_U=duckads_u

dk_ipt() {
    _fam=$1
    shift
    case "$_fam" in
        4) dk_have iptables || return 1; iptables -w 5 "$@" 2>/dev/null || iptables "$@" 2>/dev/null ;;
        6) dk_have ip6tables || return 1; ip6tables -w 5 "$@" 2>/dev/null || ip6tables "$@" 2>/dev/null ;;
    esac
}

dk_dns_targets() {
    {
        [ -r "$MODDIR/data/doh.txt" ] && cat "$MODDIR/data/doh.txt"
        [ -r "$DATA/doh.local" ] && cat "$DATA/doh.local"
    } 2>/dev/null | sed 's/\r$//; s/#.*//' | awk 'NF { print $1 }'
}

dk_system_resolvers() {
    {
        for p in net.dns1 net.dns2 net.dns3 net.dns4; do
            getprop "$p" 2>/dev/null
        done
        dumpsys connectivity 2>/dev/null |
            grep -o 'DnsAddresses: \[[^]]*\]' |
            sed 's|DnsAddresses: \[||; s|\]||' |
            tr ', ' '\n'
        dumpsys dnsresolver 2>/dev/null |
            sed -n '/DNS servers:/,/^ *$/p' |
            awk '{ print $1 }'
    } 2>/dev/null |
        sed 's|^/||; s|%.*||; s|/[0-9]*$||' |
        awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ || /^[0-9a-fA-F]*:[0-9a-fA-F:]+$/ { print }' |
        sort -u
}

dk_dns_verify() {
    dk_have ping || return 0
    for _d in android.com connectivitycheck.gstatic.com example.com; do
        if ping -c1 -w3 "$_d" 2>&1 | grep -q "^PING"; then
            return 0
        fi
    done
    return 1
}

dk_dns_gate() {
    if dk_ipt 4 -A "$DK_CHAIN_T" -m conntrack --ctstate NEW -j RETURN; then
        dk_ipt 4 -D "$DK_CHAIN_T" -m conntrack --ctstate NEW -j RETURN
        echo conntrack
        return 0
    fi
    if dk_ipt 4 -A "$DK_CHAIN_T" -m state --state NEW -j RETURN; then
        dk_ipt 4 -D "$DK_CHAIN_T" -m state --state NEW -j RETURN
        echo state
        return 0
    fi
    echo none
    return 1
}

dk_dns_reject_tcp() {
    _fam=$1
    _chain=$2
    shift 2
    dk_ipt "$_fam" -A "$_chain" -p tcp "$@" -j REJECT --reject-with tcp-reset ||
        dk_ipt "$_fam" -A "$_chain" -p tcp "$@" -j REJECT ||
        dk_ipt "$_fam" -A "$_chain" -p tcp "$@" -j DROP
}

dk_dns_reject_udp() {
    _fam=$1
    _chain=$2
    shift 2
    dk_ipt "$_fam" -A "$_chain" -p udp "$@" -j REJECT ||
        dk_ipt "$_fam" -A "$_chain" -p udp "$@" -j DROP
}

dk_dns_chain_reset() {
    for f in 4 6; do
        for c in "$DK_CHAIN_T" "$DK_CHAIN_U"; do
            dk_ipt "$f" -N "$c"
            dk_ipt "$f" -F "$c"
        done
    done
    dk_ipt 4 -F "$DK_CHAIN_T" || return 1
    return 0
}

dk_dns_hook_one() {
    _fam=$1
    _proto=$2
    _chain=$3
    _ports=$4
    _gate=$5
    set -- -p "$_proto"
    case "$_gate" in
        conntrack) set -- "$@" -m conntrack --ctstate NEW ;;
        state)     set -- "$@" -m state --state NEW ;;
    esac
    if dk_ipt "$_fam" -C OUTPUT "$@" -m multiport --dports "$_ports" -j "$_chain"; then
        return 0
    fi
    if dk_ipt "$_fam" -I OUTPUT 1 "$@" -m multiport --dports "$_ports" -j "$_chain"; then
        return 0
    fi
    _rc=1
    for p in $(echo "$_ports" | tr ',' ' '); do
        dk_ipt "$_fam" -C OUTPUT "$@" --dport "$p" -j "$_chain" && { _rc=0; continue; }
        dk_ipt "$_fam" -I OUTPUT 1 "$@" --dport "$p" -j "$_chain" && _rc=0
    done
    return $_rc
}

dk_dns_unhook() {
    for f in 4 6; do
        for c in "$DK_CHAIN_T" "$DK_CHAIN_U"; do
            _n=0
            while dk_ipt "$f" -S OUTPUT 2>/dev/null | grep -q -- "-j $c"; do
                _rule=$(dk_ipt "$f" -S OUTPUT | grep -m1 -- "-j $c" | sed 's/^-A OUTPUT //')
                [ -n "$_rule" ] || break
                # shellcheck disable=SC2086
                dk_ipt "$f" -D OUTPUT $_rule || break
                _n=$((_n + 1))
                [ "$_n" -gt 20 ] && break
            done
            dk_ipt "$f" -F "$c"
            dk_ipt "$f" -X "$c"
        done
    done
    return 0
}

dk_dns_apply() {
    if [ "$doh_block" != 1 ]; then
        dk_dns_clear
        return 0
    fi
    if ! dk_have iptables; then
        dk_log "[x] iptables not available - DNS bypass blocking needs it"
        dk_state_set doh_active 0
        return 1
    fi

    dk_dns_unhook
    dk_dns_chain_reset || { dk_log "[x] could not create the iptables chains"; return 1; }

    _gate=$(dk_dns_gate)
    _pdns=$(dk_private_dns_mode)
    _dot=$doh_dot
    if [ "$_dot" = 1 ] && [ "$_pdns" = hostname ]; then
        _dot=0
        dk_log "[!] Private DNS is set to a hostname, so port 853 is left alone - blocking it would take the phone's own DNS down"
    fi
    _ports=443
    [ "$_dot" = 1 ] && _ports="443,853"
    [ "$doh_strict" = 1 ] && _ports="$_ports,53"
    if [ "$_dot" = 1 ]; then
        dk_dns_reject_tcp 4 "$DK_CHAIN_T" --dport 853
        dk_dns_reject_tcp 6 "$DK_CHAIN_T" --dport 853
        dk_dns_reject_udp 4 "$DK_CHAIN_U" --dport 853
        dk_dns_reject_udp 6 "$DK_CHAIN_U" --dport 853
        [ "$_pdns" = opportunistic ] &&
            dk_log "[*] Private DNS is on automatic, so this downgrades the system resolver to plain DNS"
    fi

    _skip=""
    if [ "$doh_strict" = 1 ]; then
        _skip=$(dk_system_resolvers)
        [ -n "$_skip" ] && dk_log "[*] strict mode leaves the system resolvers alone: $(echo "$_skip" | tr '\n' ' ')"
    fi

    _n=0
    for ip in $(dk_dns_targets); do
        case "$ip" in
            *:*) _f=6 ;;
            *.*) _f=4 ;;
            *) continue ;;
        esac
        dk_dns_reject_tcp "$_f" "$DK_CHAIN_T" -d "$ip" --dport 443
        dk_dns_reject_udp "$_f" "$DK_CHAIN_U" -d "$ip" --dport 443
        if [ "$doh_strict" = 1 ]; then
            case "
$_skip
" in
                *"
$ip
"*) ;;
                *)
                    dk_dns_reject_tcp "$_f" "$DK_CHAIN_T" -d "$ip" --dport 53
                    dk_dns_reject_udp "$_f" "$DK_CHAIN_U" -d "$ip" --dport 53
                    ;;
            esac
        fi
        _n=$((_n + 1))
    done

    _hooked=0
    for f in 4 6; do
        dk_dns_hook_one "$f" tcp "$DK_CHAIN_T" "$_ports" "$_gate" && _hooked=$((_hooked + 1))
        dk_dns_hook_one "$f" udp "$DK_CHAIN_U" "$_ports" "$_gate" && _hooked=$((_hooked + 1))
    done

    if [ "$doh_strict" = 1 ] && [ "$DK_DNS_RETRY" != 1 ] && ! dk_dns_verify; then
        dk_log "[!] name resolution stopped working with strict mode on - rolling strict back"
        dk_cfg_set doh_strict 0
        doh_strict=0
        DK_DNS_RETRY=1
        dk_state_set doh_rollback "$(date '+%Y-%m-%d %H:%M')"
        dk_dns_apply
        return $?
    fi
    [ "$DK_DNS_RETRY" = 1 ] || dk_state_set doh_rollback ""

    dk_state_set doh_active 1
    dk_state_set doh_targets "$_n"
    dk_state_set doh_gate "$_gate"
    if [ "$_gate" = none ]; then
        dk_log "[!] this kernel has no conntrack match, so the rules are checked on every packet, not once per connection"
    fi
    dk_log "[+] DNS bypass blocking armed for $_n endpoints (gate: $_gate, $_hooked hooks)"
    return 0
}

dk_dns_clear() {
    dk_dns_unhook
    dk_state_set doh_active 0
    dk_state_set doh_targets 0
    dk_state_set doh_gate ""
    return 0
}

dk_dns_status() {
    if [ "$doh_block" != 1 ]; then
        DK_DNS_HOOKED=0
        DK_DNS_RULES=0
        echo "hooked=0 rules=0 gate="
        return 0
    fi
    _c=$(dk_ipt 4 -S "$DK_CHAIN_T" 2>/dev/null | grep -c -- "-A $DK_CHAIN_T")
    _cu=$(dk_ipt 4 -S "$DK_CHAIN_U" 2>/dev/null | grep -c -- "-A $DK_CHAIN_U")
    case "$_c" in ''|*[!0-9]*) _c=0 ;; esac
    case "$_cu" in ''|*[!0-9]*) _cu=0 ;; esac
    DK_DNS_HOOKED=0
    dk_ipt 4 -S OUTPUT 2>/dev/null | grep -q -- "-j $DK_CHAIN_T" && DK_DNS_HOOKED=1
    DK_DNS_RULES=$((_c + _cu))
    echo "hooked=$DK_DNS_HOOKED rules=$DK_DNS_RULES gate=$(dk_state_get doh_gate)"
    return 0
}

dk_private_dns_mode() {
    dk_private_dns_mode_set
    echo "$DK_PDNS"
}

dk_private_dns_mode_set() {
    [ -n "$DK_PDNS" ] && return 0
    DK_PDNS=$(settings get global private_dns_mode 2>/dev/null | tr -d '\r\n')
    [ -n "$DK_PDNS" ] || DK_PDNS=unknown
    return 0
}

dk_private_dns_off() {
    settings put global private_dns_mode off 2>/dev/null
}
