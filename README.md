# DuckAds

Systemless ad blocking for Android, built to work on as many root setups as exist rather than
on one. It fetches blocklists, turns whatever format they ship in into plain domains, and puts
the result in front of `/system/etc/hosts` using the quietest mechanism the device supports —
NoMount injection, a SUSFS open redirect, a kernel umount, a helper module, or a plain bind.

No app to install. Everything is a shell engine plus a WebUI that your root manager already
knows how to open.

```
duckads --update
```

## What makes it different

| | DuckAds |
|---|---|
| List formats | hosts, AdBlock Plus (`\|\|domain^`), dnsmasq, RPZ, unbound, plain domain lists |
| Catalog | 46 curated sources — core, aggressive, threat intel, OEM telemetry, regional, allowlists |
| Injection | probes 9 mechanisms at every boot and picks the one that hides best |
| SUSFS | registers itself automatically: `open_redirect`, `sus_mount`, `try_umount`, and a `sus_kstat` refresh after *every* rebuild |
| NoMount | first-class: the metamodule serves the file, nothing is mounted, and DuckAds calls `nomount reload` after a rebuild |
| DNS bypass | optional iptables chain that closes the DoH/DoT endpoints apps use to walk around a hosts file |
| Per-app | exemptions through NoMount's per-uid hide list, KernelSU app profiles, or the Magisk denylist |
| Scheduling | busybox crond, Wi-Fi-only, with a catch-up pass at boot when a run was missed |

## Install

Flash the zip from KernelSU, KernelSU Next, SukiSU, APatch, Magisk or MMRL, reboot, then open
the module's WebUI and press **Update now**. The first build downloads a few MB and takes
about a minute on a modern phone.

Any other module that ships a `system/etc/hosts` is disabled on install — two modules writing
the same file is how people end up with no hosts file at all.

## How a build works

```
sources ──► fetch ──► parse ──► merge ──► allowlist ──► dedupe ──► compose ──► install
            curl/    per-source  +your     remote +     sort -u    localhost   in place,
            wget     domain      blacklist your                    + your      inode kept
                     count                 whitelist               custom
```

* **Parse** normalises everything to a bare domain: lowercased, punycode kept, wildcards
  stripped, invalid labels and IP literals dropped. AdBlock rules survive only when they are
  pure domain rules — anything with a path, a `*`, or a `domain=` modifier is discarded rather
  than mangled.
* **Allowlist** removes a domain and its subdomains. `=example.com` matches exactly,
  `re:^ads[0-9]+\.` is a regular expression. Remote allowlists (the `@@||` rules in HaGeZi's
  whitelists) are merged in automatically.
* **Dedupe** is a plain `sort -u`. Nothing else is removed: a hosts file matches exact names,
  so dropping `ads.example.com` because `example.com` is blocked would silently unblock it.
* **Install** writes into the existing file rather than replacing it, so a bind mount, an open
  redirect and a NoMount injection all stay valid across an update.

If every source fails, or filtering leaves nothing, the existing hosts file is kept and the
run is reported as failed. DuckAds never leaves you with an empty hosts file.

## Injection modes

Probed at every boot, best first. `duckads --status` says which one is live and why.

| Mode | Needs | Hidden from detection |
|---|---|---|
| `nomount` | NoMount metamodule | yes — nothing is mounted at all |
| `susfs_redirect` | SUSFS `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | yes — no mount, opens are redirected |
| `zn_redirect` | zn-hostsredirect + Zygisk Next | yes — the helper injects |
| `ap_redirect` | APatch kernel `hosts_file_redirect` | yes — kernel-side redirect |
| `ksud_umount` | ksud with `kernel umount` | yes — bound, then unmounted per app |
| `susfs_bind` | SUSFS `try_umount` | yes — bound, kstat spoofed, unmounted per app |
| `overlay` | overlayfs | no — a visible mount on `/system/etc` |
| `bind` | any root | no — visible unless something else hides it |
| `mount` | magic-mount managers | no — the manager owns the mount |

A Zygisk denylist handler (ReZygisk, NoHello, Zygisk Assistant, NeoZygisk, Zygisk Next with
enforcement) also makes a plain bind safe, and DuckAds takes that into account.

Force one with `duckads --mode susfs_bind` if you are debugging; `auto` is the default and
re-probes at every boot, so moving to a different kernel or manager needs no action.

### SUSFS autobind

When SUSFS is present DuckAds registers itself without being asked:

* `susfs_redirect` — `add_open_redirect /system/etc/hosts <module hosts>` with uid scheme 2,
  falling back to the two-argument form on older builds.
* `susfs_bind` — `add_sus_kstat` **before** the bind, `update_sus_kstat` after it, then
  `add_sus_mount` and `add_try_umount … 1`.
* `overlay` — `add_sus_mount /system/etc` plus `add_try_umount`.

The part most modules miss: a rebuild changes the file's size and mtime, so a kstat recorded
at boot stops matching. DuckAds re-runs `update_sus_kstat` after every single rebuild, and
re-arms the open redirect at boot.

### NoMount

If `/data/adb/metamodule` resolves to `nomount` or `meta-nomount`, DuckAds drops to zero
mounts and leaves `skip_mount` off so the engine injects `system/etc/hosts` like any other
module file. After a rebuild it calls `nomount reload` so the new content is served without a
reboot.

## DNS bypass blocking

A hosts file only binds apps that ask Android to resolve a name. An app that speaks DoH to a
hard-coded `1.1.1.1` never asks. Turn on **Block encrypted-DNS endpoints** and DuckAds builds
`duckads_t` and `duckads_u` chains in iptables and ip6tables, entered only for new connections
on the DNS ports:

* TCP and UDP 443 to ~60 known resolver IPs (Google, Cloudflare, Quad9, AdGuard, NextDNS,
  Mullvad, ControlD, OpenDNS, Yandex, Ali, DNSPod and friends — see `module/data/doh.txt`)
* port 853 everywhere, for DNS-over-TLS, optional
* port 53 to those same IPs in strict mode, for apps that hard-code a plain resolver. The
  resolvers your own network handed you are read out of `dumpsys connectivity` and
  `dumpsys dnsresolver` and left alone, so strict mode cannot cut the phone off its own DNS —
  and if name resolution stops working anyway, DuckAds notices, rolls strict back on its own
  and says so in the log

Add your own endpoints in the **DNS IPs** rule tab. The list-catalog entries *HaGeZi DoH
bypass* and *DoH + VPN + proxy bypass* cover the name side of the same problem.

Android's own **Private DNS** (DoT) does *not* skip the hosts file — the system resolver still
reads it first, so blocking keeps working with it on. DuckAds shows its state on the Settings
tab because it is the setting people expect to matter, and offers to turn it off if you want
plain DNS for other reasons. What does walk around the hosts file is an app shipping its own
DoH client, which is what the chains above are for.

## Performance

A hosts blocker can slow a phone down in exactly two places. DuckAds is built so neither one
costs you anything you can feel, and ships the means to check rather than asking you to trust it.

**Name lookups.** The system resolver consults the hosts file on its way to every lookup, and a
name that is *not* in the file means scanning all of it. So the only thing that matters is length:

* pick the tier that fits the device — Light or Small resolve as fast as no list at all,
  Ultimate and Xtra are hundreds of thousands of lines
* the IPv6 sink is off by default, because it doubles the file for no extra blocking
* `max_entries` caps the file when you want a hard ceiling
* a build over 250 000 entries says so in the log
* blocked names are *faster* than normal ones: they are answered from the file with no DNS
  query at all

Measure it on your own device:

```bash
duckads --bench
```

It times a lookup of the first blocked name in the file against the last one. The difference is
what your list length costs per lookup — everything else in that number is your device, not
DuckAds. The WebUI has the same thing behind **Measure lookup cost** on the Status tab.

**Throughput.** The DNS-bypass chains are entered only for *new connections* on the DNS ports:

```
-p tcp -m conntrack --ctstate NEW -m multiport --dports 443,853 -j duckads_t
```

A download, a video stream or a speed test never walks a single DuckAds rule — the rules see the
first packet of a connection and nothing after it. If a kernel has no conntrack match, DuckAds
falls back to a plain port match and says so on the Settings tab instead of quietly costing you
per-packet CPU. Blocked endpoints are rejected with a TCP reset rather than dropped, so an app
that tries DoH fails instantly and falls back to system DNS instead of stalling on a timeout.

**Everything else.** No daemon and no watcher: the engine runs when you ask it to, plus one
crond entry when a schedule is set. Updates run at `nice 19` and idle I/O priority, can be
capped with a download speed limit, are Wi-Fi-only by default and default to 04:00.

## Per-app exemptions

An exempt app reads the untouched hosts file — its ads come back, which is the point when a
banking app or a game refuses to run with blocking on. The mechanism is whatever your setup
provides, in this order:

| Mechanism | How | Precision |
|---|---|---|
| NoMount | `nomount uid block <pkg>` | per-uid, no mounts involved |
| KernelSU | app profile with `umount_modules` | per-app, kernel-enforced |
| Magisk | `magisk --denylist add <pkg>` | per-app, needs the denylist on |

The Apps tab says which one is in use, and says so plainly when none is available.

## Rules

Four files, all under `/data/adb/duckads`, all editable from the WebUI:

| File | Meaning |
|---|---|
| `blacklist.txt` | extra domains to block, one per line |
| `whitelist.txt` | domains to spare; a domain frees its subdomains too. `=exact.com`, `re:regex` |
| `custom.txt` | raw hosts lines copied in untouched (LAN names, pins) |
| `doh.local` | extra DNS endpoint IPs for the bypass blocker |

## Settings worth knowing

| Setting | Default | Why change it |
|---|---|---|
| `sink` | `0.0.0.0` | `127.0.0.1` if something on the device dislikes the null route |
| `ipv6_sink` | off | adds a `::` line per domain; doubles the file |
| `max_entries` | 0 | cap the file on devices where huge hosts files slow lookups |
| `keep_system_hosts` | on | merges the ROM's own entries back in on every build |
| `update_schedule` | weekly | `off`, `daily`, `weekly`, `monthly`, `custom` cron |
| `wifi_only` | on | skip scheduled runs on mobile data |
| `update_rate_limit` | 0 | cap the download rate of an update, e.g. `500k` |

## Command line

`duckads` is symlinked into your manager's bin directory, so it works from Termux or adb shell.

```
duckads --status                  what is running right now
duckads --update                  fetch every enabled list and rebuild
duckads --reset                   drop the blocklist, keep your rules
duckads --enable | --disable      pause and resume blocking
duckads --mode auto|<mode>        force an injection mode
duckads --catalog                 the curated catalog as JSON
duckads --source on|off|rm <id>   toggle a catalog list
duckads --source add <url>        subscribe to your own list
duckads --block <domain>          one-off block
duckads --allow <domain>          one-off allow
duckads --rules get|put|add|del|clear <file>
duckads --exempt add|rm|list <package>
duckads --dns on|off|status       encrypted-DNS blocking
duckads --schedule off|daily|weekly|monthly|custom [expr]
duckads --bench                   what the hosts file costs a name lookup
duckads --log [lines]
```

`--json` as the first argument turns `--status`, `--catalog` and `--apps` into machine-readable
documents; that is what the WebUI consumes.

## Files

```
/data/adb/duckads/
  config.sh        settings, quoted key=value
  sources.list     state|kind|id|url|label
  sources.stat     id|domains|result from the last run
  blacklist.txt whitelist.txt custom.txt doh.local
  exempt.list      packages allowed to bypass
  hosts.orig       the ROM's hosts file, snapshotted before anything was mounted
  hosts.bak        the previous good build
  state            counters and timestamps
  mode.sh          the mode this boot decided on
  duckads.log      rotated at 256 KB
/data/adb/modules/duckads/system/etc/hosts   the built file
```

Uninstalling removes the module and its runtime state but keeps your rules and settings.

## Troubleshooting

**Blocking stopped after a manager or kernel change.** The mode is re-probed at every boot, so
a reboot is usually the whole fix. `duckads --status` will show the new mode.

**`live_app` says apps do not see it.** The file is built but the injection is not reaching
apps — check that no other hosts module was re-enabled, and that the mode is not `bind` on a
setup where something unmounts it.

**A site broke.** Add it on the Rules tab under Allow and rebuild. If a whole list is too
aggressive, turn it off in the catalog — Pro++, Ultimate and 1Hosts Xtra break things by design.

**The build takes minutes.** Large tiers parse millions of lines. Use Light or Small, or set
`max_entries`.

**AdAway is installed.** Reset AdAway's hosts file first; two writers means neither wins.

## Credits

The mode-probing idea and the hard-won knowledge of which manager needs which trick come from
[bindhosts](https://github.com/bindhosts/bindhosts) by xx and KOWX712. DuckAds is a separate
implementation, not a fork, but it stands on that map of the territory.

Blocklists belong to their maintainers — StevenBlack, HaGeZi, OISD, AdAway, AdGuard, 1Hosts,
Peter Lowe, Dan Pollock, notracking, Frogeye, abuse.ch, EasyList and anti-AD. Please support
them.

Author: XxxY. Licensed GPL-3.0.
