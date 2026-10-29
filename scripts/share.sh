#!/bin/bash
# =============================================================================
# share.sh - Turn on the VPN-branded hotspot: broadcast your VPN *country* IP
#            to client devices over a Mac Wi-Fi hotspot.
#
# Run when you need it:   bash scripts/share.sh
#
# Why this exists: macOS refuses to start a Wi-Fi hotspot when the sharing
# source is a VPN interface. This uses a physical uplink (iPhone USB tether or
# USB-C->ethernet adapter) so macOS WILL broadcast, then inserts a pf NAT rule
# so the hotspot clients egress out the VPN tunnel instead of the physical
# uplink. Net result: a client laptop joining the hotspot gets the VPN's public
# IP (your chosen country), not your local ISP's IP.
#
# Prereqs (checked, script stops if missing):
#   - a physical uplink interface carrying internet (not Wi-Fi)
#   - a VPN connected, with its tunnel as the default route
# Prompts for your Mac admin password once (edits nat + pf as root).
# Safe / reversible. Nothing persistent - run revert.sh (or reboot) to teardown.
# =============================================================================
set -u

# ---- CONFIG: adjust for your setup ------------------------------------------
UPLINK_IFACE="${UPLINK_IFACE:-en5}"        # physical uplink: iPhone USB = en5, or your USB-ethernet iface
TUN_IFACE="${TUN_IFACE:-utun4}"            # VPN tunnel interface (find: route -n get 8.8.8.8 | grep interface)
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-192.168.2.0/24}"
HOTSPOT_NAME="${HOTSPOT_NAME:-Prakaash Chand}"  # must match your Sharing Wi-Fi network name
# -----------------------------------------------------------------------------

echo "==> [1/4] Checking physical uplink (${UPLINK_IFACE})..."

if ifconfig "$UPLINK_IFACE" 2>/dev/null | grep -q "status: active" && ifconfig "$UPLINK_IFACE" 2>/dev/null | grep -q "inet "; then
    echo "  ok: uplink up -> $(ifconfig "$UPLINK_IFACE" | grep 'inet ' | awk '{print $2}')"
else
    echo "  FAIL: ${UPLINK_IFACE} is not carrying internet."
    echo "  If using iPhone tether: unlock iPhone, Settings > Personal Hotspot ON,"
    echo "  'Allow Others to Join' ON, keep it plugged and unlocked. Then rerun."
    echo "  If using a USB-C ethernet adapter: plug a cable from it into your router."
    exit 1
fi

echo "==> [2/4] Checking VPN tunnel is the active route (${TUN_IFACE})..."

if route -n get 8.8.8.8 2>/dev/null | grep -q "interface: ${TUN_IFACE}"; then
    PUBIP=$(curl -s --max-time 6 ifconfig.me 2>/dev/null)
    echo "  ok: default route is through ${TUN_IFACE}. Public IP: ${PUBIP}"
    echo "      (that is the country the laptop will show)"
else
    echo "  FAIL: default route is NOT through ${TUN_IFACE}."
    echo "  Connect your VPN first (pick the country server you want), then rerun."
    exit 1
fi

echo "==> [3/4] Enabling Internet Sharing (${UPLINK_IFACE} -> Wi-Fi), needs admin password..."
# Pops the macOS admin password prompt via osascript.
osascript <<'APPLESCRIPT' 2>/dev/null
do shell script "
  PLIST=/Library/Preferences/SystemConfiguration/com.apple.nat.plist
  /usr/libexec/PlistBuddy -c 'Set :NAT:Enabled 1' \"$PLIST\" || true
  /usr/libexec/PlistBuddy -c 'Set :NAT:AirPort:Enabled 1' \"$PLIST\" || true
" with administrator privileges
APPLESCRIPT
if [ "$?" -eq 0 ]; then
    echo "  ok: sharing preference set."
else
    echo "  WARN: could not auto-set sharing pref; you may need to toggle it in System Settings."
fi

echo "==> [4/4] Applying pf NAT so hotspot clients egress out the tunnel (needs admin)..."
PF_CONF="/tmp/tunnel-nat-$$.conf"
cat > "$PF_CONF" <<CSET
scrub-anchor "com.apple/*"
nat on ${TUN_IFACE} inet from ${HOTSPOT_SUBNET} to any -> (${TUN_IFACE})
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
CSET
osascript -e "do shell script \"/sbin/pfctl -e -f $PF_CONF\" with administrator privileges" 2>/dev/null
rm -f "$PF_CONF"
NAT_FIRST=$(osascript -e 'do shell script "/sbin/pfctl -s nat" with administrator privileges' 2>/dev/null | head -1)
if echo "$NAT_FIRST" | grep -q "nat on ${TUN_IFACE}"; then
    echo "  ok: pf rule active (hotspot clients exit via ${TUN_IFACE})."
else
    echo "  FAIL: pf rule did not apply. First NAT line was: $NAT_FIRST"
    exit 1
fi

echo
echo "=============================================================================="
echo "  ALL SET. Final step (needed on some macOS builds):"
echo "  System Settings > General > Sharing > Internet Sharing"
echo "     Share from: ${UPLINK_IFACE}  ->  to: Wi-Fi   (switch ON, click Start)"
echo "  The hotspot '${HOTSPOT_NAME}' will broadcast with the tunnel-country IP."
echo "  Connect your client to it and check ifconfig.me - it should show the VPN"
echo "  country, not your local ISP. Tear down later with  bash scripts/revert.sh"
echo "  (or just turn Internet Sharing OFF / unplug the phone)."
echo "=============================================================================="
