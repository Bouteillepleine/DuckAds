DK_CHAIN=duckads

dk_ipt() {
    _fam=$1
    shift
    case "$_fam" in
        4) dk_have iptables || return 1; iptables "$@" 2>/dev/null ;;
        6) dk_have ip6tables || return 1; ip6tables "$@" 2>/dev/null ;;
    esac
}

dk_dns_targets() {
    {
        [ -r "$MODDIR/data/doh.txt" ] && cat "$MODDIR/data/doh.txt"
        [ -r "$DATA/doh.local" ] && cat "$DATA/doh.local"
    } 2>/dev/null | sed 's/\r$//; s/#.*//' | awk 'NF { print $1 }'
}

dk_dns_reject() {
    _fam=$1
    shift
    dk_ipt "$_fam" -A "$DK_CHAIN" "$@" -j REJECT ||
        dk_ipt "$_fam" -A "$DK_CHAIN" "$@" -j DROP
}

dk_dns_chain_reset() {
    _fam=$1
    dk_ipt "$_fam" -N "$DK_CHAIN"
    dk_ipt "$_fam" -F "$DK_CHAIN" || return 1
    return 0
}

dk_dns_hook() {
    _fam=$1
    dk_ipt "$_fam" -C OUTPUT -j "$DK_CHAIN" && return 0
    dk_ipt "$_fam" -I OUTPUT 1 -j "$DK_CHAIN"
}

dk_dns_unhook() {
    _fam=$1
    while dk_ipt "$_fam" -C OUTPUT -j "$DK_CHAIN"; do
        dk_ipt "$_fam" -D OUTPUT -j "$DK_CHAIN" || break
    done
    dk_ipt "$_fam" -F "$DK_CHAIN"
    dk_ipt "$_fam" -X "$DK_CHAIN"
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

    _n4=0
    _n6=0
    dk_dns_chain_reset 4 || { dk_log "[x] could not create the iptables chain"; return 1; }
    dk_dns_chain_reset 6

    if [ "$doh_dot" = 1 ]; then
        dk_dns_reject 4 -p tcp --dport 853
        dk_dns_reject 4 -p udp --dport 853
        dk_dns_reject 6 -p tcp --dport 853
        dk_dns_reject 6 -p udp --dport 853
    fi

    for ip in $(dk_dns_targets); do
        case "$ip" in
            *:*) _f=6 ;;
            *.*) _f=4 ;;
            *) continue ;;
        esac
        dk_dns_reject "$_f" -d "$ip" -p tcp --dport 443
        dk_dns_reject "$_f" -d "$ip" -p udp --dport 443
        if [ "$doh_strict" = 1 ]; then
            dk_dns_reject "$_f" -d "$ip" -p udp --dport 53
            dk_dns_reject "$_f" -d "$ip" -p tcp --dport 53
        fi
        [ "$_f" = 4 ] && _n4=$((_n4 + 1)) || _n6=$((_n6 + 1))
    done

    dk_dns_hook 4
    dk_dns_hook 6
    dk_state_set doh_active 1
    dk_state_set doh_targets "$((_n4 + _n6))"
    dk_log "[+] DNS bypass blocking armed for $((_n4 + _n6)) endpoints"
    return 0
}

dk_dns_clear() {
    dk_dns_unhook 4
    dk_dns_unhook 6
    dk_state_set doh_active 0
    dk_state_set doh_targets 0
    return 0
}

dk_dns_status() {
    _c=$(dk_ipt 4 -S "$DK_CHAIN" | grep -c "^-A $DK_CHAIN")
    case "$_c" in ''|*[!0-9]*) _c=0 ;; esac
    _h=0
    dk_ipt 4 -C OUTPUT -j "$DK_CHAIN" && _h=1
    echo "$_h|$_c"
}

dk_private_dns_mode() {
    settings get global private_dns_mode 2>/dev/null | tr -d '\r\n'
}

dk_private_dns_off() {
    settings put global private_dns_mode off 2>/dev/null
}
