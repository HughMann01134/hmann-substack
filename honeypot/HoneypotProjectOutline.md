# Raspberry Pi Honeypot — Project Setup Outline

A VPS-fronted, Pi-hosted honeypot on a **cellular** uplink. The VPS is the
internet-facing endpoint; the Raspberry Pi 4 (2GB) does the honeypot work behind a
WireGuard tunnel; a **Teltonika RUT956** industrial LTE router provides the internet
connection *and* the network isolation (it replaces the home internet + separate-VLAN
step). Software: **DShield honeypot** (SSH/Telnet + web) plus **Dionaea** (malware
capture) in Docker. A **7" DSI touchscreen** on the Pi runs a local text status
dashboard (`honeypot-status.py`).

---

## Architecture at a glance

```
   ┌───────────┐   DNAT    ┌────────────────┐   WireGuard tunnel     ┌────────────────────┐
   │ Internet  │──────────►│      VPS       │   (carried over the    │  Raspberry Pi 4    │
   │ attackers │           │  public IP     │◄═══ cellular link) ═══►│  2GB               │
   └───────────┘           │  WG · DNAT     │                        │  DShield + Dionaea │
                           │  egress filter │                        │  ── WG endpoint ── │
                           └────────────────┘                        │  7" status console │
                                                                     └─────────┬──────────┘
                                                                               │ isolated
                                                                               │ LAN port
                                                          ┌────────────────────┴──────────┐
                                                          │      Teltonika RUT956          │
                                                          │  LTE Cat 4 · dual SIM · eSIM   │
                                                          │  data-limit cap · VLAN · FW    │
                                                          │  failover · watchdog           │
                                                          │  ▸ only uplink = cellular ◂    │
                                                          └────────────────────────────────┘

   Physical path: attacker → VPS public IP → into the WireGuard tunnel → over the uplink
   through the RUT956 → Pi. The RUT956's only uplink faces the internet (cellular SIM or a
   phone hotspot via WiFi WAN — see Uplink options) and the Pi sits on an isolated LAN
   port, so the honeypot has no path to the home network at any point.

   Default: WireGuard runs on the Pi; the RUT956 is a pure uplink (just NATs the Pi out).
   Alternative: terminate WireGuard on the RUT956 itself — see Phase 3.
```

- **VPS** — public IP, WireGuard peer, DNAT of honeypot ports, egress filtering.
- **RUT956** — the uplink *and* the isolation boundary: LTE Cat 4, dual SIM + eSIM, WiFi (station/AP), RutOS (OpenWrt-based) with data-limit cap, VLAN, firewall, and native failover/connection watchdog.
- **Pi** — runs the honeypots on an isolated LAN port behind the RUT956; by default holds the WireGuard endpoint and dials out to the VPS. The 7" DSI touchscreen shows the local status TUI on the console.
- **Tunnel** — WireGuard, `PersistentKeepalive = 25` on the peer behind NAT (the Pi, by default).

---

## Uplink options

The design only needs *outbound* connectivity, so several uplinks work — attackers see the VPS IP regardless — but they differ a lot in control and safety. Ranked:

1. **RUT956 + its own prepaid SIM (recommended).** Cleanest: RutOS's hard data-limit cap, SMS alerts, and dual-SIM auto-switch all apply (the data limit works only on a *Mobile*-protocol interface). Full isolation / firewall / WG / watchdog on purpose-built hardware.
2. **RUT956 with WiFi-WAN → phone hotspot (good fallback).** The phone is just the internet source; the RUT956 still does isolation, firewall, WireGuard, and connection watchdog/reconnect. Caveats:
   - **The hard data cap moves to the phone.** RutOS's mobile data limit + SMS only applies to a SIM (Mobile-protocol) interface, *not* WiFi WAN. Set the phone's own data warning/limit and lean on the carrier plan. The RUT956 can still show usage graphs and shape speed (QoS/SQM), but it won't auto-cut at a limit on WiFi WAN.
   - **Phone hotspot must be 2.4 GHz** — the RUT956's WiFi 4 (802.11b/g/n) radio is 2.4 GHz only.
   - **Keep the Pi wired** to a LAN port so the single WiFi radio is dedicated to the WAN uplink (don't run AP + station on one radio).
   - **Routed, not bridged.** Use WiFi as a NAT'd WAN so the Pi stays firewalled behind the RUT956; bridging WAN↔LAN would flatten the Pi onto the phone's network and kill the isolation.
   - **Dedicated phone**, hotspot auto-sleep/timeout disabled, kept on 24/7.
   - If you *also* keep a SIM in the RUT956 as failover, watch for background traffic (RMS/MQTT, etc.) leaking over the mobile interface — people have hit surprise bills where mobile data burned despite WiFi being primary. Run no SIM, or restrict/monitor the mobile interface.
3. **Phone hotspot straight to the Pi (last resort).** Works, but you lose every RUT956 control (cap, failover, watchdog, firewall/isolation). Prefer routing the hotspot through the RUT956's WiFi WAN (option 2).
4. **Public WiFi — excluded for the live honeypot.** Captive portals and outbound UDP/port filtering routinely break a headless WireGuard dial-out, and — more importantly — you'd be running attack-attracting infra and storing live malware on a network you don't own, risking other users and the venue's IP and breaking their AUP. Only ever point the RUT956's WiFi WAN at a network *you* own/control (home lab, a site you manage).

---

## Status display (7" console)

The official Raspberry Pi 7" touchscreen (800×480, DSI ribbon) shows a text TUI —
`honeypot-status.py` (rich-based) — directly on the framebuffer console. No
X/Wayland/browser kiosk: ~30–50 MB instead of 300–500 MB, which matters on the 2 GB box.

- **Local data only — it never polls the RUT956.** Phase 2 firewalls the Pi off the router's control plane; the dashboard must not reopen that hole. If you want RSRP/signal bars, read them from the router on some *other* device.
- **Panels:** `VPS TUNNEL` — green/yellow/red from WireGuard handshake age (falls back to pinging the VPS tunnel IP if WG terminates on the RUT956) · `CONNECTIONS` — Cowrie attempt count, unique IPs, recent user/pass tries · `MALWARE CAPTURED` — Dionaea sample counts + recent, with src IP/service from its SQLite · `SYSTEM` — CPU/RAM/swap/disk/temp plus vnstat data today/month (the on-screen cap-watch).
- **Console setup:** bigger font via `sudo dpkg-reconfigure console-setup` → Terminus ~10x20 (≈80×24, what the layout is sized for) or 12x24; `consoleblank=0` in `/boot/firmware/cmdline.txt` so the screen stays lit; brightness via `/sys/class/backlight/*/brightness`.
- **Auto-start:** raspi-config → console autologin on tty1, then in `~/.bash_profile`: `[ "$(tty)" = "/dev/tty1" ] && exec sudo python3 /path/to/honeypot-status.py` — runs fullscreen at boot (root, which `wg` needs), getty respawns it if it exits, SSH sessions unaffected.
- **Edit the script's CONFIG block** to match the build: `COWRIE_JSON`, `DIONAEA_BINARIES`, `DIONAEA_SQLITE`, `WG_INTERFACE`, `VPS_PING_TARGET`, `DISK_MOUNT`, `VNSTAT_IFACE`. Panels show "waiting for honeypot" until DShield/Dionaea exist, then light up on their own.
- **Self-view caveat:** on-screen counts are the honeypot's own report — a glance indicator only. The trusted record is the off-box copy (Phase 5).

---

## Core design decisions (don't undo these)

These are the choices that are easy to forget and expensive to get wrong. The *why* matters as much as the *what*.

- **2GB → DShield + Dionaea only. No T-Pot.** T-Pot needs 8–16GB + Docker/ELK. It will not run here.
- **Preserve the attacker's source IP.** Never plain SNAT/masquerade on the VPS — the Pi would see the VPS as the source of everything and you'd lose the real attacker IP, which is the entire value of a honeypot. Use **DNAT-only + policy routing on the Pi**, or **route all Pi traffic through the VPS as its gateway** (also centralizes egress filtering — see Phase 6). Holds regardless of where WireGuard terminates.
- **The RUT956 = the honeypot's isolation.** Its only uplink faces the internet and the Pi hangs off an isolated LAN port, so the honeypot is a self-contained island with no path to the home LAN. This replaces the old "VLAN / second router" step.
- **Default: WireGuard on the Pi, RUT956 as a pure uplink.** Then the router only ever forwards an *encrypted* tunnel — it never handles decrypted attack traffic, and its own attack-prevention can't accidentally filter your honeypot data. (Alternative: terminate WG on the RUT956 — if so, set `AllowedIPs` to include the Pi's LAN address, do **not** masquerade it on the LAN side, add a firewall forward rule, and keep DNAT-only at the VPS, so source IPs survive.)
- **Cap the data — location depends on the uplink.** With a SIM in the RUT956: RutOS hard limit + SMS alert (+ optional dual-SIM auto-switch). With a phone hotspot over WiFi WAN: RutOS's hard cap doesn't apply (it's SIM-only) — set the cap on the phone instead. Pair either with VPS-side filtering.
- **Confirm the North American band variant of the RUT956.** The EU-band SKU (B1/B3/B7/B8/B20/B28) underperforms on SaskTel/Telus.
- **Assume the Pi will be compromised.** That's its job. So: (a) it stays isolated behind the RUT956, and (b) logs living only on the Pi can't be trusted — ship them off-box.
- **SSD fixes durability, not trust.** The SSD saves the card from wear; it does **not** protect logs from tampering. Keep a trusted copy off-box regardless.
- **Dionaea's HTTP/HTTPS modules OFF.** They collide with DShield's web honeypot on 80/443. Let DShield own SSH/Telnet + web; let Dionaea own SMB + databases + file services.
- **Run Dionaea in Docker** (`dinotools/dionaea`). Dodges its stale-build problems on current Pi OS, and gives isolation + one-command teardown on a box that literally stores live malware.
- **zram for RAM spikes, not an SD swap file.** Dionaea can balloon under active capture; zram absorbs it with no card wear.
- **Separate management plane.** Real admin SSH = non-standard port, key-only, firewalled to your IP. It is never the honeypot. Same idea for the RUT956's own admin interface.

---

## Phased build checklist

### Phase 0 — Planning & prerequisites
- [ ] Read the cloud provider's AUP (most allow honeypots; egress controls keep you compliant).
- [ ] Isolation is provided by the RUT956 (separate router, internet-only uplink) — see Phase 2. No home-LAN VLAN work needed.
- [ ] Decide the uplink source: RUT956 SIM (recommended) vs. phone hotspot via WiFi WAN — see Uplink options.
- [ ] Decide which services to expose (full set, or just SMB + databases). This sets your DNAT list.
- [ ] Gather hardware: Pi 4 (2GB), **known-good USB-SATA enclosure** + SSD + quality cable, **Teltonika RUT956 (confirm North American band variant)**, official **7" DSI touchscreen** (status display), and a prepaid data SIM **or** a dedicated phone hotspot (per the uplink choice).
- [ ] Provision the VPS.

### Phase 1 — Base Pi setup (OS, storage, software, hardening)
- [ ] Flash **Raspberry Pi OS Lite** (headless — never the desktop).
- [ ] Bootstrap on temporary home WiFi (setup only — never the live uplink): `sudo raspi-config nonint do_wifi_country CA` (unblocks the radio), then `sudo nmcli device wifi connect "SSID" password "PASS"`.
- [ ] `sudo apt update && sudo apt full-upgrade -y` (reboot if kernel/firmware moved).
- [ ] Install project packages — **apt, not pip** (Bookworm's Python is externally managed, and the status script runs as root at boot so the libs must be system-wide; if a pinned venv is ever wanted later, use **uv** rather than pip): `sudo apt install -y git docker.io docker-compose vnstat wireguard-tools tmux python3-rich python3-psutil` then `sudo systemctl enable --now vnstat`.
- [ ] SSD: either **boot the whole Pi from it** (Pi 4 native USB boot, cleanest), or keep SD boot and mount the SSD for the write-heavy dirs. Mount with `noatime`.
- [ ] Verify no USB resets: check `dmesg` under load. If you see UAS resets/dropouts, add a `usb-storage.quirks` entry in `cmdline.txt`. (A drive dropping mid-write corrupts Dionaea's SQLite DB.)
- [ ] Enable **zram** swap.
- [ ] Harden management SSH: key-only, non-standard port, firewalled to your admin IP.
- [ ] Baseline host firewall.
- [ ] Set up the 7" status display (console font, `consoleblank=0`, tty1 autologin → dashboard) — see **Status display** section.

### Phase 2 — Network isolation (via the RUT956, before any exposure)
- [ ] Connect the Pi to an isolated LAN port / VLAN on the RUT956 (wired — keep the WiFi radio free for a WiFi-WAN uplink if used).
- [ ] **Remove the temporary setup-WiFi profile**: `nmcli connection delete "SSID"` — no home-network credentials on a box built to be attacked.
- [ ] Lock down RutOS management: change default credentials, disable WebUI/SSH from the WAN side, and firewall the Pi's segment off from the router's own admin interface — a popped Pi must not reach the router's control plane.
- [ ] Keep any WiFi WAN **routed/NAT'd, not bridged**, so the Pi stays behind the RUT956 firewall.
- [ ] Decide on Teltonika RMS: convenient, but it's another remote-management path into the router. Enable only if you want it.
- [ ] Confirm the only inbound path to the Pi is your management SSH, and the Pi can't reach the router admin or any other segment.

### Phase 3 — VPS + WireGuard tunnel
- [ ] **Decide where WireGuard terminates** (default: on the Pi):
  - **On the Pi (default):** the RUT956 just NATs the Pi out. Install WG on the Pi and VPS; the Pi initiates with `PersistentKeepalive = 25`. Nothing special on the router.
  - **On the RUT956 (alternative):** the router holds the tunnel, the Pi sits on the LAN. Set `AllowedIPs` on the VPS peer to include the Pi's LAN subnet/address, route it over WG, **don't masquerade it on the LAN side**, and add a RutOS firewall rule forwarding the DNAT'd traffic to the Pi. (Status screen then uses its ping fallback for tunnel state.)
- [ ] Assign tunnel IPs (e.g. VPS `10.10.0.1`, endpoint `10.10.0.2`).
- [ ] Verify the tunnel (ping across the `10.10.0.0/24` link both ways).
- [ ] On the VPS: enable `ip_forward`, add **DNAT** rules for the honeypot ports → the honeypot's tunnel/LAN IP.
- [ ] Implement source-IP preservation (DNAT-only at the VPS; policy routing on the Pi, *or* route all Pi traffic via the VPS). Holds regardless of where WG terminates.
- [ ] **Verify from an external host** that the Pi's logs show the real client IP, not the VPS.

### Phase 4 — Honeypot software
- [ ] Install the **DShield honeypot** (Cowrie SSH 22→2222 / Telnet 23→2223, web honeypot on 80, firewall logging). Register with the ISC.
- [ ] Reconcile DShield's iptables rules with your management + isolation rules.
- [ ] Deploy **Dionaea via Docker** (`dinotools/dionaea`):
  - [ ] Disable the `http` and `https` services (collision with DShield web).
  - [ ] Map the ports you chose: SMB 445, MSSQL 1433, MySQL 3306, MongoDB 27017, FTP 21, TFTP 69/udp, SIP 5060 (add UPnP/EPMAP if wanted).
  - [ ] Volume-mount the SSD for the binary store **and** the SQLite DB.
- [ ] Watch iptables ordering: Docker and DShield both manipulate iptables — confirm chains don't clobber each other.
- [ ] Point `honeypot-status.py`'s CONFIG paths at the actual Cowrie log + Dionaea dirs.

### Phase 5 — Logging & off-box shipping
- [ ] DShield → ISC (built in).
- [ ] Cowrie → emit JSON to a collector on the VPS.
- [ ] Dionaea → rsync captured binaries off-box periodically.
- [ ] Confirm the **trusted copy** lives somewhere the Pi can't reach/tamper.

### Phase 6 — Egress filtering, data cap & containment
- [ ] **Cap the data** where the uplink allows it: with a RUT956 SIM, set a hard RutOS mobile data limit + SMS alert (optionally dual-SIM auto-switch); with a phone-hotspot/WiFi-WAN uplink, set the cap on the phone (RutOS's hard cap is SIM-only) and optionally add QoS/SQM speed shaping on the RUT956.
- [ ] Drop junk at the VPS: only DNAT the ports you care about, so the metered link never carries traffic you don't want.
- [ ] Default-deny the Pi's outbound traffic. Allow only: WireGuard to VPS, DNS, DShield/ISC submission, OS updates.
- [ ] If the Pi routes all traffic via the VPS, enforce this **at the VPS** (single choke point).
- [ ] Note: with WG on the Pi, the RUT956's built-in attack-prevention protects the *router* and doesn't touch honeypot traffic (it's encrypted in the tunnel). Don't rely on it to filter honeypot data.
- [ ] Goal: a compromised honeypot can't scan or attack others (outbound abuse = VPS termination + complaints to you).

### Phase 7 — Verification & testing
- [ ] Each exposed honeypot port answers from the internet (via the VPS).
- [ ] Attacker source IPs appear correctly in logs.
- [ ] Logs are arriving off-box.
- [ ] Pi cannot reach the home LAN (or the RUT956 admin plane).
- [ ] Egress allow-list holds (blocked destinations are actually blocked).
- [ ] Data cap/alert actually fires (RutOS threshold on SIM, or the phone-side limit on WiFi WAN).
- [ ] If using two SIMs / a failover WAN, failover switches as expected.
- [ ] Status screen: `VPS TUNNEL` shows green with the tunnel up (and flips red if you drop it), and the Connections/Malware panels populate once the honeypots are live.
- [ ] RAM headroom sane under some load; zram engaging on spikes.

### Phase 8 — Ongoing operations
- [ ] Use the RUT956's native connection watchdog / auto-reboot and WAN failover for uplink resilience (no hand-rolled watchdog needed).
- [ ] Monitor data usage (status screen vnstat figures, RutOS usage graphs, phone-side counter for WiFi WAN, or RMS if enabled) so you catch a runaway before the cap.
- [ ] Monitor RAM (Dionaea spikes) and SSD usage/health.
- [ ] Prune local data periodically (it's shipped off anyway).
- [ ] Handle captured malware safely — never execute on the Pi; ship off for analysis.
- [ ] Keep a re-image/teardown plan ready (assume eventual compromise; Docker makes Dionaea a one-command rebuild).
- [ ] Patch the management plane (Pi OS, WireGuard, Docker, **and RutOS**) — never the honeypot services.

---

## Port & parameter reference

| Purpose | Port(s) / Value | Notes |
|---|---|---|
| Uplink | RUT956 SIM *or* phone hotspot via WiFi WAN | WiFi WAN = 2.4 GHz, routed not bridged (see Uplink options) |
| RUT956 | Teltonika RUT956 | LTE Cat 4 (150/50); **confirm NA band variant** |
| Data cap | RutOS mobile limit (SIM) *or* phone-side limit (WiFi WAN) | RutOS hard cap + SMS is SIM-only |
| Status display | official 7" DSI touchscreen, 800×480 | text TUI on the console — no X/browser kiosk |
| Status script | `honeypot-status.py` | local-only (never polls the RUT956); edit its CONFIG block |
| WireGuard termination | Pi (default) | alt: on the RUT956 — see Phase 3 |
| Pi LAN IP (behind RUT956) | e.g. `192.168.1.10` | on an isolated RUT956 LAN port/VLAN |
| Management SSH | non-standard port | key-only, firewalled to admin IP — **not** the honeypot |
| WireGuard | 51820/udp (default) | on the VPS; Pi dials out |
| Tunnel subnet | 10.10.0.0/24 | VPS `.1`, endpoint `.2` (example) |
| DShield — Cowrie SSH | 22 → 2222 | |
| DShield — Cowrie Telnet | 23 → 2223 | |
| DShield — web honeypot | 80 | Dionaea must not also bind this |
| Dionaea — SMB | 445 | primary malware bait |
| Dionaea — MSSQL / MySQL / MongoDB | 1433 / 3306 / 27017 | |
| Dionaea — FTP / TFTP | 21 / 69udp | |
| Dionaea — SIP | 5060 | optional |
| Dionaea — HTTP / HTTPS | **disabled** | conflicts with DShield web |
| WireGuard keepalive | `PersistentKeepalive = 25` | on the peer behind NAT |

> Note: DShield's firewall logs connection attempts to ports it isn't handling and reports them to the ISC. Any port Dionaea binds becomes *answered* rather than logged-and-dropped — expected, just be aware the ISC view of those ports changes.

---

## Open items to pin down

- [ ] Cloud provider (affects WireGuard/firewall specifics).
- [ ] **Uplink source: RUT956 SIM (recommended) vs. phone hotspot via WiFi WAN.**
- [ ] **WireGuard termination: on the Pi (default) vs. on the RUT956.**
- [ ] **Confirm the RUT956 is the North American band variant.**
- [ ] Exact Dionaea service scope (all protocols vs. SMB + databases only).
- [ ] Source-IP preservation method (DNAT + policy routing vs. all-traffic-via-VPS).

*When you reach any phase and want the actual configs — WireGuard for both ends, the
RUT956/RutOS setup (WG, WiFi WAN, VLAN, data limit, firewall), the nftables/iptables
DNAT with source-IP preservation, the Dionaea Compose file, or the Cowrie off-box log
forwarding — generate them then. The status dashboard is already written:
`honeypot-status.py`, deployed per the Status display section.*
