#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARSE="$ROOT/module/lib/parse.awk"
FILTER="$ROOT/module/lib/filter.awk"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/in.txt" <<'EOF'
# comment
! adblock comment
[Adblock Plus 2.0]
0.0.0.0 ads.example.com
0.0.0.0 track.example.com # trailing comment
127.0.0.1 metrics.Example.NET
:: v6sink.example.org
255.255.255.255 broadcasthost
127.0.0.1 localhost
::1 ip6-localhost
0.0.0.0 doubleclick.net analytics.doubleclick.net
||abp.example.com^
||abp2.example.com^$third-party
||abp3.example.com^$domain=foo.com
||abp4.example.com/path^
@@||allowed.example.com^
example.org##.ad-banner
address=/dnsmasq.example.com/0.0.0.0
server=/dnsmasqs.example.com/
local-zone: "rpz.example.com" always_nxdomain
rpzcname.example.com CNAME .
plaindomain.example.com
*.wildcard.example.com
UPPER.EXAMPLE.COM
192.168.1.10 nas.local
notadomain
-bad.example.com
bad-.example.com
1.2.3.4
EOF

awk -f "$PARSE" -v ALLOW="$TMP/allow" "$TMP/in.txt" | LC_ALL=C sort -u > "$TMP/got"

cat > "$TMP/want" <<'EOF'
abp.example.com
abp2.example.com
ads.example.com
analytics.doubleclick.net
dnsmasq.example.com
dnsmasqs.example.com
doubleclick.net
metrics.example.net
plaindomain.example.com
rpz.example.com
rpzcname.example.com
track.example.com
upper.example.com
v6sink.example.org
wildcard.example.com
EOF

diff -u "$TMP/want" "$TMP/got" || { echo "parser output changed"; exit 1; }
grep -qx "allowed.example.com" "$TMP/allow" || { echo "abp exception not routed to the allowlist"; exit 1; }

printf 'example.org\n=plaindomain.example.com\nre:^abp[0-9]*\\.\n' > "$TMP/wl"
awk -f "$FILTER" -v WL="$TMP/wl" "$TMP/got" > "$TMP/kept"
grep -q "v6sink.example.org" "$TMP/kept" && { echo "suffix allowlist did not apply"; exit 1; }
grep -q "^plaindomain.example.com$" "$TMP/kept" && { echo "exact allowlist did not apply"; exit 1; }
grep -q "^abp2" "$TMP/kept" && { echo "regex allowlist did not apply"; exit 1; }
grep -q "^ads.example.com$" "$TMP/kept" || { echo "allowlist removed too much"; exit 1; }

grep -q "^analytics.doubleclick.net$" "$TMP/kept" || { echo "a subdomain was dropped - a hosts file matches exact names, so every one must survive"; exit 1; }
grep -q "^doubleclick.net$" "$TMP/kept" || { echo "the parent domain was dropped"; exit 1; }

echo "parser and allowlist behave, and no subdomain was suppressed"
