#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE="$ROOT/module"
OUT="$ROOT/release"
VER=$(sed -n 's/^version=//p' "$MODULE/module.prop")
CODE=$(sed -n 's/^versionCode=//p' "$MODULE/module.prop")
ZIP="$OUT/DuckAds-$VER.zip"

for f in duckads.sh service.sh post-fs-data.sh boot-completed.sh customize.sh uninstall.sh action.sh \
         lib/common.sh lib/modes.sh lib/engine.sh lib/dns.sh lib/exempt.sh lib/sched.sh; do
    sh -n "$MODULE/$f" || { echo "syntax error in $f"; exit 1; }
done
awk -f "$MODULE/lib/parse.awk" /dev/null
awk -f "$MODULE/lib/filter.awk" -v WL=/dev/null /dev/null

if grep -rlU $'\r' "$MODULE" --exclude='*.png' > /dev/null 2>&1; then
    echo "CRLF found in module sources:"
    grep -rlU $'\r' "$MODULE" --exclude='*.png'
    exit 1
fi

mkdir -p "$OUT"
rm -f "$ZIP"
if command -v zip > /dev/null 2>&1; then
    ( cd "$MODULE" && zip -qr9 "$ZIP" . -x '*.DS_Store' -x 'system/etc/hosts' )
else
    python "$ROOT/scripts/mkzip.py" "$MODULE" "$ZIP"
fi

cat > "$ROOT/update.json" <<EOF
{
  "version": "$VER",
  "versionCode": $CODE,
  "zipUrl": "https://github.com/Bouteillepleine/DuckAds/releases/download/$VER/DuckAds-$VER.zip",
  "changelog": "https://raw.githubusercontent.com/Bouteillepleine/DuckAds/main/CHANGELOG.md"
}
EOF

echo "built $ZIP"
python - "$ZIP" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
print(len(names), "entries")
bad = [n for n in names if "\\" in n]
if bad:
    print("backslash entries:", bad)
    sys.exit(1)
for need in ("module.prop", "duckads.sh", "webroot/index.html", "lib/parse.awk",
             "META-INF/com/google/android/update-binary"):
    if need not in names:
        print("missing", need)
        sys.exit(1)
print("layout ok")
PY
