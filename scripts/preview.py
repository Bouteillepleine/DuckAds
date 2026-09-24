import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(ROOT, "module", "webroot", "index.html")
dst = os.path.join(ROOT, "preview.html")
html = io.open(src, encoding="utf-8").read()

status = {
    "version": "v1.0.0", "versionCode": 10000, "enabled": 1,
    "mode": "susfs_bind", "mode_setting": "auto", "mode_label": "bind + SUSFS autobind",
    "mode_auto": "susfs_bind", "mode_reason": "SUSFS try_umount available", "hidden": 1,
    "manager": "KernelSU Next", "susfs": "v1.5.9", "nomount": 0,
    "blocked": 193826, "custom": 2, "sources_enabled": 4, "sources_ok": 4, "sources_fail": 0,
    "last_update": "2026-09-24 08:40", "build_seconds": 52,
    "hosts_path": "/data/adb/modules/duckads/system/etc/hosts", "hosts_size": 5427962,
    "live_root": 1, "live_app": 1,
    "schedule": "weekly", "schedule_expr": "0 4 * * 6", "crond": 1,
    "doh": {"enabled": 1, "hooked": 1, "rules": 126, "strict": 0, "dot": 1,
            "gate": "conntrack", "private_dns": "off"},
    "bench": {"when": "2026-09-24 08:41", "entries": 193830, "scan_ms": 41, "delta_cms": 180},
    "exempt": {"mech": "ksud", "label": "KernelSU app profile (umount modules)", "count": 2},
    "settings": {"enabled": "1", "mode": "auto", "sink": "0.0.0.0", "ipv6_sink": "0",
                 "compact": "1", "max_entries": "0", "keep_system_hosts": "1",
                 "update_schedule": "weekly", "update_cron": "", "update_hour": "4",
                 "update_rate_limit": "0", "wifi_only": "1", "doh_block": "1",
                 "doh_strict": "0", "doh_dot": "1", "exempt_enabled": "1", "notify": "1",
                 "lists_seeded": "1"},
    "error": "",
}

catalog = []
for line in io.open(os.path.join(ROOT, "module", "data", "catalog.tsv"), encoding="utf-8"):
    if not line.strip():
        continue
    i, kind, cat, name, default, url, note = line.rstrip("\n").split("\t")
    catalog.append({"id": i, "kind": kind, "cat": cat, "name": name, "url": url, "note": note,
                    "state": "on" if default == "1" else "off",
                    "count": 76510 if default == "1" else 0,
                    "result": "ok" if default == "1" else ""})

apps = [{"pkg": p, "exempt": 1 if p in ("com.bank.app", "org.example.game") else 0} for p in [
    "com.android.chrome", "com.bank.app", "org.example.game", "com.spotify.music",
    "com.whatsapp", "org.mozilla.firefox", "com.reddit.frontpage",
    "com.Gcenter.WindWings.SpaceShooter.Premium", "com.airfrance.android.dinamoprd",
    "com.amazon.avod.thirdpartyclient"]]

bench = {"entries": 193830, "bytes": 5427962, "scan_ms": 41, "top_cms": 120,
         "bottom_cms": 300, "delta_cms": 180,
         "verdict": "a few milliseconds per lookup - fine in practice"}

rules = "doubleclick.net\\n=googleadservices.com\\nre:^metrics[0-9]*\\\\.\\n"
log = ("2026-09-24 08:40:02 [>] hagezi-multi\\n"
       "2026-09-24 08:40:31     162636 domains\\n"
       "2026-09-24 08:40:54 [+] blocked: 193826 | custom: 2 | sources: 4 ok, 0 failed | 52s")

stub = """
<script>
window.ksu = {
  exec: function (cmd, opts, cb) {
    var out = "";
    if (cmd.indexOf("--status") >= 0) out = %s;
    else if (cmd.indexOf("--catalog") >= 0 || cmd.indexOf("--sources") >= 0) out = %s;
    else if (cmd.indexOf("--apps") >= 0) out = %s;
    else if (cmd.indexOf("--bench") >= 0) out = %s;
    else if (cmd.indexOf("--rules get") >= 0) out = "%s";
    else if (cmd.indexOf("--log") >= 0) out = "%s";
    setTimeout(function () { window[cb](0, out, ""); }, 40);
  }
};
</script>
""" % (
    json.dumps(json.dumps(status)),
    json.dumps(json.dumps(catalog)),
    json.dumps(json.dumps(apps)),
    json.dumps(json.dumps(bench)),
    rules,
    log,
)

marker = '<script>\n"use strict";'
if marker not in html:
    raise SystemExit("could not find the page script to stub")
html = html.replace(marker, stub + marker, 1)
io.open(dst, "w", encoding="utf-8", newline="\n").write(html)
print(dst)
