# DuckAds

Systemless ad blocking for Android. Builds a hosts file from blocklists and serves it with
whatever your root setup supports: NoMount injection, a SUSFS open redirect, a kernel umount,
a helper module, or a plain bind.

Shell engine plus a WebUI. No app to install.

## Install

Flash the zip from KernelSU, KernelSU Next, SukiSU, APatch, Magisk or MMRL. Reboot, open the
WebUI, hit **Update**.

Any other module shipping `system/etc/hosts` is disabled on install. Two writers means neither
wins.

## What it does

- 46 curated lists (StevenBlack, HaGeZi tiers, OISD, AdAway, 1Hosts, OEM telemetry, regional)
  plus any URL you add
- Parses hosts, AdBlock `||domain^`, dnsmasq, RPZ and plain domain lists
- Probes the injection mode at every boot and registers with SUSFS when it is there
- Optional iptables chain that closes the DoH/DoT endpoints apps use to walk around the hosts file
- Per-app exemptions through NoMount's uid hide list, KernelSU app profiles or the Magisk denylist
- Scheduled updates, Wi-Fi only, at an hour you pick

## Modes

Probed best-first. `duckads --status` says which is live and why.

| mode | needs | hidden |
|---|---|---|
| `nomount` | NoMount metamodule | yes, nothing is mounted |
| `susfs_redirect` | SUSFS `OPEN_REDIRECT` | yes, no mount |
| `zn_redirect` | zn-hostsredirect + Zygisk Next | yes |
| `ap_redirect` | APatch `hosts_file_redirect` | yes |
| `ksud_umount` | ksud `kernel umount` | yes |
| `susfs_bind` | SUSFS `try_umount` | yes, kstat spoofed |
| `overlay` | overlayfs | no |
| `bind` | any root | no |
| `mount` | magic mount | no |

Force one with `duckads --mode <name>`. `auto` re-probes every boot.

SUSFS registration is automatic, including a `sus_kstat` refresh after every rebuild, not just
at boot. A rebuild changes size and mtime, so a kstat taken at boot stops matching.

## Rules

Under `/data/adb/duckads`, editable from the WebUI:

| file | meaning |
|---|---|
| `blacklist.txt` | extra domains to block |
| `whitelist.txt` | domains to spare, subdomains too. `=exact.com`, `re:regex` |
| `custom.txt` | raw hosts lines, copied in untouched |
| `doh.local` | extra DNS endpoint IPs for the bypass blocker |

No subdomain suppression: a hosts file matches exact names, so dropping `ads.example.com`
because `example.com` is blocked would silently unblock it.

## Command line

```
duckads --status                 what is running
duckads --update                 fetch and rebuild
duckads --reset                  drop the blocklist, keep your rules
duckads --mode auto|<mode>       force an injection mode
duckads --source on|off|rm <id>  toggle a list
duckads --source add <url>       subscribe to your own
duckads --block|--allow <domain>
duckads --exempt add|rm <pkg>
duckads --dns on|off             DoH / DoT blocking
duckads --schedule off|daily|weekly|monthly|custom [expr]
duckads --bench                  what the hosts file costs a lookup
duckads --log
```

## Speed

The resolver reads the hosts file on the way to every lookup, so length is the only cost.
`duckads --bench` measures it against its own noise floor and refuses to report a figure below
it. On an OP15 with 6 000 and with 76 000 entries the difference came out below the floor.

The DNS chains are entered only for new connections on the DNS ports, so a download never walks
them. Blocked endpoints get a TCP reset, not a drop, so an app fails over instantly instead of
hanging on a timeout.

## Credits

Blocklists belong to their maintainers: StevenBlack, HaGeZi, OISD, AdAway, AdGuard, 1Hosts,
Peter Lowe, Dan Pollock, notracking, Frogeye, abuse.ch, EasyList, anti-AD. Support them.

The mode-probing idea comes from [bindhosts](https://github.com/bindhosts/bindhosts). DuckAds is
a separate implementation.

GPL-3.0.
