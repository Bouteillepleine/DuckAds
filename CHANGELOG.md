# Changelog

## v1.0.0

- first release
- hosts engine with hosts / AdBlock / dnsmasq / RPZ / plain-domain parsing
- 46-source curated catalog with per-source domain counts
- nine injection modes, probed at every boot
- SUSFS autobind, including a kstat refresh after every rebuild
- NoMount metamodule support with `nomount reload` after a rebuild
- DoH / DoT bypass blocking through an iptables chain
- per-app exemptions via NoMount, KernelSU app profiles or the Magisk denylist
- scheduled updates with a Wi-Fi-only guard and a boot catch-up pass
- WebUI: status, lists, rules, apps, settings

## v1.0.1

- DNS-bypass rules are entered only for new connections (conntrack/state gate), so bulk traffic never walks them
- TCP rejects use a reset so a blocked DoH attempt fails instantly instead of stalling
- strict mode leaves the resolvers your own network handed you alone
- duckads --bench measures what the hosts file costs a name lookup, with a WebUI button
- updates run at nice 19 / idle I/O and take an optional download rate cap
- a build over 250k entries says so
