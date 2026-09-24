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

## v1.0.2

- FIX: dropped parent-domain compaction entirely. A hosts file matches exact names, so suppressing a subdomain whose parent is blocked silently unblocked it - on StevenBlack that was 34k domains, including googleads.g.doubleclick.net
- FIX: status JSON was invalid on Android. mksh treats a bare | in a pattern as alternation, so ${var%|*} stripped everything and the WebUI got "live_root":, - helpers now return values in variables
- port 853 is left alone when Private DNS is set to a hostname, which would otherwise take the phone's own DNS down
- Private DNS is described accurately: Android's DoT still reads the hosts file, so blocking keeps working with it on

## v1.0.3

- the WebUI was slow because every list row and every package spawned its own awk and grep: catalog and app listings are now a single awk pass (Lists 4.2s to 0.09s, Apps 6.5s to 0.15s on an OP15)
- status assembled without ~40 subshells (1.6s to 0.6s)
- DNS status skips iptables entirely when blocking is off

## v1.0.4

- FIX: the system-resolver exemption never matched anything. Android prints DNS servers with a leading slash (/41.1.239.252) and the parser stripped from the first slash, leaving an empty list - strict mode could have blocked the resolver a router handed out
- resolvers are now read from dumpsys connectivity and dumpsys dnsresolver
- after arming strict mode DuckAds checks that names still resolve, and rolls strict back by itself if they do not
- All apps leaves out RRO overlays and auto-generated RROs, which are resources rather than apps that resolve names
- long package names wrap instead of sliding under the toggle

## v1.0.5

- header theme and refresh buttons are SVG icons at a 44px touch target instead of tiny text glyphs, and the refresh icon spins while it works

## v1.0.6

- the lookup benchmark takes the minimum of 14 samples instead of a mean, so ping's own fork cost cancels out instead of drowning the signal (a 76k-entry file measures a steady 3.9ms, not a noisy 0-10ms)
- the RRO filter also catches auto_generated_characteristics_rro, .rro.oneplus and .overlay.target, which the suffix-only match let through

## v1.0.7

- the lookup benchmark now calibrates its own noise floor by timing the same name twice, and refuses to report a figure below it. The 3.9ms and 12.1ms it reported before were per-name variance, not scan cost - a control run showed the middle and last entries of the file timing identically
- the scan time is labelled as the upper bound it is (an awk pass, where the resolver uses C)

## v1.0.8

- secondary text was too dark to read on the dark theme: the faint token sat at 3.5:1 contrast against the card, now 6:1, with the muted token and the light theme raised to match
- description, hint and note text goes from 11.5px to 12.5px

## v1.0.9

- root manager detection asks the manager's own binary instead of trusting environment variables a fork may not set: a KernelSU Next build that reports KSU_NEXT=false was being shown as plain KernelSU
- recognises KernelSU, KernelSU Next, SukiSU, SukiSU Ultra, APatch, Magisk, Magisk Delta, Magisk Alpha and Kitsune Magisk, with the version shown under the name
- scripts/test-managers.sh covers all thirteen branches with stubbed binaries, and runs in CI
- the hosts path in the Status card wraps at its slashes instead of sliding under the size
