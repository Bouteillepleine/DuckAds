dk_sched_expr_set() {
    DK_SCHED_EXPR=$(dk_sched_expr)
    return 0
}

dk_sched_expr() {
    _h=$update_hour
    case "$_h" in ''|*[!0-9]*) _h=4 ;; esac
    [ "$_h" -gt 23 ] && _h=4
    case "$update_schedule" in
        off)     echo "" ;;
        daily)   echo "0 $_h * * *" ;;
        weekly)  echo "0 $_h * * 6" ;;
        monthly) echo "0 $_h 1 * *" ;;
        custom)  echo "$update_cron" ;;
        *)       echo "0 $_h * * 6" ;;
    esac
}

dk_cron_valid() {
    _e=$1
    [ -n "$_e" ] || return 1
    case "$_e" in
        @reboot|@hourly|@midnight|@daily|@weekly|@monthly|@annually|@yearly) return 0 ;;
        *[\`\$\;\&\|\<\>\'\"]*) return 1 ;;
    esac
    set -f
    set -- $_e
    set +f
    [ "$#" = 5 ] || return 1
    for f in "$@"; do
        case "$f" in
            *[!0-9,/*-]*) return 1 ;;
        esac
    done
    return 0
}

dk_crond_running() {
    pgrep -f "crond -bc $DATA/crontabs" > /dev/null 2>&1
}

dk_sched_apply() {
    mkdir -p "$DATA/crontabs"
    _expr=$(dk_sched_expr)
    if [ -z "$_expr" ]; then
        rm -f "$DATA/crontabs/root" 2>/dev/null
        dk_sched_stop
        dk_state_set schedule "off"
        return 0
    fi
    if ! dk_cron_valid "$_expr"; then
        dk_log "[x] rejected cron expression: $_expr"
        return 1
    fi
    echo "$_expr /system/bin/sh $MODDIR/duckads.sh --update --cron > /dev/null 2>&1" > "$DATA/crontabs/root"
    chmod 0600 "$DATA/crontabs/root" 2>/dev/null
    dk_state_set schedule "$_expr"
    dk_crond_running && dk_sched_stop
    busybox crond -bc "$DATA/crontabs" -L /dev/null 2>/dev/null
    return 0
}

dk_sched_stop() {
    for p in $(pgrep -f "crond -bc $DATA/crontabs" 2>/dev/null); do
        kill "$p" 2>/dev/null
    done
    return 0
}

dk_sched_due() {
    _last=$(dk_state_get last_update_epoch)
    case "$_last" in ''|*[!0-9]*) return 0 ;; esac
    _now=$(date +%s)
    case "$update_schedule" in
        off) return 1 ;;
        daily)   _win=86400 ;;
        weekly)  _win=604800 ;;
        monthly) _win=2592000 ;;
        *)       _win=604800 ;;
    esac
    [ "$((_now - _last))" -ge "$_win" ]
}
