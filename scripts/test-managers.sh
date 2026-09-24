#!/usr/bin/env bash
# Exercises dk_manager_name_set against stubbed manager binaries.
set -uo pipefail
set +u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
fail=0

stub() {
    printf '#!/bin/sh\n%s\n' "$2" > "$TMP/bin/$1"
    chmod +x "$TMP/bin/$1"
}

check() {
    local label=$1 want=$2
    shift 2
    local got
    got=$(
        export PATH="$TMP/bin:/usr/bin:/bin"
        export DK_ROOT="$TMP/root" MODDIR="$ROOT/module"
        unset KSU KSU_NEXT APATCH MAGISK_VER_CODE KSU_VER_CODE KSU_KERNEL_VER_CODE APATCH_VER_CODE
        eval "$*"
        . "$ROOT/module/lib/common.sh" 2>/dev/null
        dk_manager_name_set
        printf '%s' "$DK_MANAGER"
    )
    if [ "$got" = "$want" ]; then
        printf '  %-42s %s\n' "$label" "$got"
    else
        printf '  %-42s GOT %-18s WANT %s\n' "$label" "$got" "$want"
        fail=$((fail + 1))
    fi
    rm -f "$TMP/bin"/*
}

echo "root manager detection:"

stub ksud 'echo "KernelSU Next userspace cli"'
check "ksud banner says KernelSU Next" "KernelSU Next" 'true'

stub ksud 'echo "SukiSU Ultra userspace cli"'
check "ksud banner says SukiSU Ultra" "SukiSU Ultra" 'true'

stub ksud 'printf "KernelSU userspace cli\n\nCommands:\n  kpm   Manage KPM\n"'
check "generic banner but has a kpm command" "SukiSU" 'true'

stub ksud 'printf "KernelSU userspace cli\n\nCommands:\n  module  Manage modules\n"'
check "plain upstream KernelSU" "KernelSU" 'true'

stub ksud 'echo "some unrelated tool"'
check "unrecognised ksud, env says Next" "KernelSU Next" 'KSU=true; KSU_NEXT=true'

stub ksud 'echo "some unrelated tool"'
check "unrecognised ksud, env says KSU only" "KernelSU" 'KSU=true'

stub magisk 'case "$1" in -c) echo "28.1" ;; esac'
check "magisk -c reports a stock version" "Magisk" 'true'

stub magisk 'case "$1" in -c) echo "27.0-delta" ;; esac'
check "magisk -c reports delta" "Magisk Delta" 'true'

stub magisk 'case "$1" in -c) echo "26.4-kitsune" ;; esac'
check "magisk -c reports kitsune" "Kitsune Magisk" 'true'

stub magisk 'case "$1" in -c) echo "27.0-alpha" ;; esac'
check "magisk -c reports alpha" "Magisk Alpha" 'true'

stub apd 'echo "10672"'
check "apd present" "APatch" 'true'

stub apd 'echo "10672"'
stub ksud 'echo "KernelSU Next userspace cli"'
check "APatch wins when both are present" "APatch" 'APATCH=true'

check "nothing installed" "unknown" 'true'

echo
if [ "$fail" -gt 0 ]; then
    echo "$fail case(s) wrong"
    exit 1
fi
echo "every manager branch resolves correctly"
