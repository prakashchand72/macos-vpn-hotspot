#!/bin/bash
# =============================================================================
# revert.sh - Tear down everything and return the Mac to NORMAL.
# Run when done:   bash scripts/revert.sh
# - Turns OFF Internet Sharing (clears the persisted Enabled flag)
# - Restores pf to Apple's clean defaults (drops the tunnel nat override)
# - Leaves internet on your normal home Wi-Fi, exactly as before
# Requires your Mac admin password once (to edit nat + pf as root).
# Safe / reversible. Nothing here persists into anything harmful.
# =============================================================================
set -u

# ---- CONFIG: keep in sync with share.sh -------------------------------------
TUN_IFACE="${TUN_IFACE:-utun4}"            # must equal share.sh's TUN_IFACE
# -----------------------------------------------------------------------------

echo "==> [1/3] Turning OFF Internet Sharing (clears persisted state)..."
osascript <<'APPLESCRIPT' 2>/dev/null
do shell script "
  PLIST=/Library/Preferences/SystemConfiguration/com.apple.nat.plist
  /usr/libexec/PlistBuddy -c 'Set :NAT:Enabled 0' \"$PLIST\" || true
  /usr/libexec/PlistBuddy -c 'Set :NAT:AirPort:Enabled 0' \"$PLIST\" || true
  /usr/libexec/PlistBuddy -c 'Set :NAT:PrimaryInterface:Enabled 0' \"$PLIST\" || true
" with administrator privileges
APPLESCRIPT
if [ "$?" -eq 0 ]; then
    echo "  ok: sharing preference cleared (Enabled=0)."
else
    echo "  WARN: could not auto-clear sharing pref; toggle it OFF in System Settings."
fi

echo "==> [2/3] Restoring pf to Apple defaults (dropping tunnel nat rule)..."
osascript -e 'do shell script "/sbin/pfctl -f /etc/pf.conf" with administrator privileges' 2>/dev/null
NAT_FIRST=$(osascript -e 'do shell script "/sbin/pfctl -s nat" with administrator privileges' 2>/dev/null | head -1)
if echo "$NAT_FIRST" | grep -q "nat on ${TUN_IFACE}"; then
    echo "  FAIL: tunnel rule still present. Re-run, or reset in Terminal:  sudo pfctl -f /etc/pf.conf"
else
    echo "  ok: pf back to Apple defaults (tunnel nat rule gone)."
fi

echo "==> [3/3] Confirming Mac is back to normal home Wi-Fi..."
DEFAULT_IF=$(route -n get 8.8.8.8 2>/dev/null | awk '/interface:/{print $2}')
PUBIP=$(curl -s --max-time 6 ifconfig.me 2>/dev/null)
echo "  default route interface: ${DEFAULT_IF}"
echo "  public IP: ${PUBIP}"
echo
echo "  If that shows your normal home router/ISP IP, you are back to normal."
echo "  (During VPN sharing it was ${TUN_IFACE} / a foreign-country IP.)"
echo
echo "  Tip: unplug the phone too. Nothing else needs to change."
