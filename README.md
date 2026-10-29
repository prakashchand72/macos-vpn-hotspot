# macOS VPN Hotspot

Turn your Mac into a secure hotspot that broadcasts **your VPN country IP** to other devices (laptops, tablets, phones) — without installing anything on the client.

Works when your Mac's own internet comes over a **physical interface like an iPhone USB tether**, then shares that tunneled connection over Wi-Fi so a locked-down laptop can egress through the VPN country's IP.

## Why this exists

The big macOS gotcha this solves:

- macOS **refuses to broadcast a Wi-Fi hotspot when the sharing source is a VPN interface** (it silently sets `AirPort.Enabled = 0`). Picking "ProtonVPN" or "utun4" as the source never produces a Wi-Fi AP.
- But macOS **will** broadcast when the source is a *physical* interface (Ethernet, iPhone USB tether, etc.).
- The catch: sharing a physical source sends clients out that interface (your ISP's IP), **not** the VPN.

So this repo does both halves:
1. Uses a **physical source** (iPhone USB tether or a USB-C ethernet adapter) so macOS actually starts the Wi-Fi AP.
2. Inserts a small **pf NAT override** so the hotspot clients egress out the VPN tunnel (`utun4`) instead of the physical uplink.

Result: the laptop joins your Mac's hotspot and gets a public IP in the **VPN's country**, not your local ISP's.

```
Client laptop ─WiFi─> Mac hotspot ──> VPN tunnel (utun4) ──> Internet (VPN country IP)
                 (192.168.2.x)      ...phone/ethernet cable uplink
```

## What you need

- A Mac (Apple Silicon or Intel, macOS 13+ works; tested on 27.x)
- A VPN client on the Mac that creates a tunnel interface (Proton VPN, WireGuard, Tailscale, Mullvad, etc.)
- A **physical uplink** for the Mac's internet that is NOT Wi-Fi, so the Wi-Fi radio is free to broadcast:
  - **iPhone USB tether** (plug in + Personal Hotspot on) OR
  - **USB-C → Ethernet adapter + cable to your router**

## Setup (one time)

1. **Reserve the tunnel interface.** The scripts default to `TUN_IFACE=utun4`. If your VPN uses a different interface, set it at the top of the scripts or override per-run with environment variables. Same for the physical uplink and hotspot name:
   ```bash
   # find the tunnel interface: connect the VPN, then
   #   route -n get 8.8.8.8 | grep interface
   TUN_IFACE="utun4"                # your VPN tunnel interface
   UPLINK_IFACE="en5"               # your physical uplink (iPhone USB=en5, or USB-ethernet iface)
   HOTSPOT_SUBNET="192.168.2.0/24"
   HOTSPOT_NAME="Prakaash Chand"    # must match your Sharing Wi-Fi network name
   ```
   Edit those lines at the top of `scripts/share.sh` (and `TUN_IFACE` in `revert.sh`), or pass them inline:
   ```bash
   TUN_IFACE=utun4 UPLINK_IFACE=en5 bash scripts/share.sh
   ```

2. **Name your hotspot** the same as `HOTSPOT_NAME` in the scripts, or update the scripts to match your actual Sharing network name.

## Usage

Turn it **ON** when you need it:
```bash
bash scripts/share.sh
```

Turn it **OFF / back to normal** when done:
```bash
bash scripts/revert.sh
```

### What `share.sh` does
1. Checks the physical uplink (iPhone USB / ethernet) is carrying internet.
2. Checks the VPN tunnel is the live default route.
3. Enables Internet Sharing (physical source → Wi-Fi) — prompts for your admin password.
4. Installs the pf NAT override so hotspot clients egress out the tunnel, and verifies it's first in the NAT table.

### What `revert.sh` does
1. Turns Internet Sharing fully OFF (clears the persisted `com.apple.nat.plist` flag that survives reboot).
2. Restores pf to Apple's clean defaults (drops the tunnel nat rule).
3. Confirms you're back on your normal home-Wi-Fi public IP.

## The one manual click

Some macOS builds only start the Wi-Fi AP from the **System Settings GUI**, no matter what a script sets. `share.sh` prints the exact one-time step:

```
System Settings > General > Sharing > Internet Sharing
    Share from: <your physical uplink>   ->   to: Wi-Fi   (switch ON, click Start)
```

That's the only GUI touch. Everything else (prereq checks, admin-password prompts, pf rules) is scripted.

## Important notes

- **Not reboot-persistent by design.** The pf override resets on reboot; that's intentional — run `share.sh` only when you need the hotspot. Nothing load at boot, no lingering daemon.
- **Speed is capped by the uplink.** If you tether via iPhone mobile data, expect mobile-data speeds. A USB-C→ethernet adapter into your router uses full ISP speed and is the sturdier option.
- **Security posture:** this opens a WPA2 hotspot (set a strong password in Wi-Fi Options) and adds a NAT rule. It does **not** open ports or weaken your firewall. Reversible in one command.
- **Corporate caution:** if you're relocating a locked-down work laptop to appear in another country, make sure that's within your employer's policy. This is a networking tool, not a policy bypass.

## Project layout

```
macos-vpn-hotspot/
├── scripts/
│   ├── share.sh      # turn on: checks + enabling + pf override
│   └── revert.sh     # turn off: clean teardown back to normal
├── LICENSE
└── README.md
```

## License

MIT — see [LICENSE](LICENSE).
