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
