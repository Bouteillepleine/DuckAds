#!/usr/bin/env bash
set -uo pipefail

CATALOG=${1:-"$(dirname "$0")/../module/data/catalog.tsv"}
PARSE="$(dirname "$0")/../module/lib/parse.awk"
fail=0

while IFS=$'\t' read -r id kind cat name def url note; do
    [ -n "${id:-}" ] || continue
    case "$id" in \#*) continue ;; esac
    tmp=$(mktemp)
    code=$(curl -sL --max-time 90 -o "$tmp" -w '%{http_code}' "$url")
    if [ "$code" != 200 ]; then
        printf '%-34s HTTP %s  %s\n' "$id" "$code" "$url"
        fail=$((fail + 1))
        rm -f "$tmp"
        continue
    fi
    if [ "$kind" = allow ]; then
        n=$(awk -f "$PARSE" -v ALLOWMODE=1 "$tmp" | sort -u | wc -l)
    else
        n=$(awk -f "$PARSE" "$tmp" | sort -u | wc -l)
    fi
    size=$(wc -c < "$tmp")
    if [ "$n" -lt 20 ]; then
        printf '%-34s PARSED %s domains from %s bytes  <-- suspicious\n' "$id" "$n" "$size"
        fail=$((fail + 1))
    else
        printf '%-34s ok %8s domains  (%s bytes)\n' "$id" "$n" "$size"
    fi
    rm -f "$tmp"
done < "$CATALOG"

echo
if [ "$fail" -gt 0 ]; then
    echo "$fail source(s) need attention"
    exit 1
fi
echo "catalog is healthy"
