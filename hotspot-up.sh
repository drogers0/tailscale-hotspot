#!/bin/bash
# Tailscale Wi-Fi hotspot bring-up with self-heal fallback.
#
# Brings wlan0 up as an AP whose clients egress via the Tailscale exit node.
# If the AP fails to come up, reverts to the "vuDevices" client connection and
# clears the exit node so the Pi stays reachable (no stranding).
#
# Deployed to /usr/local/sbin/hotspot-up.sh and run on boot by
# tailscale-hotspot.service. Values below mirror .env for the live deployment.
set -u
EXIT_NODE=100.83.81.60          # Tailscale IP of the exit node (desktop-ju87id5)
WLAN=wlan0
TS=tailscale0
SUB=10.77.0.0/24
LOG=/var/log/hotspot-up.log
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') hotspot-up start ==="

# 1. IP forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# 2. Exit node (clients tunnel through this)
tailscale set --exit-node="$EXIT_NODE" --exit-node-allow-lan-access=true

# 3. Forwarding + NAT for the hotspot subnet -> tailscale0 (idempotent)
iptables -C FORWARD -i "$WLAN" -o "$TS" -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD 1 -i "$WLAN" -o "$TS" -j ACCEPT
iptables -C FORWARD -i "$TS" -o "$WLAN" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD 1 -i "$TS" -o "$WLAN" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -C POSTROUTING -s "$SUB" -o "$TS" -j MASQUERADE 2>/dev/null \
  || iptables -t nat -I POSTROUTING 1 -s "$SUB" -o "$TS" -j MASQUERADE

# 4. Bring up the AP
nmcli connection up Hotspot
sleep 8

# 5. Verify the AP actually came up; self-heal if not
if iw dev "$WLAN" info 2>/dev/null | grep -q "type AP"; then
  echo "AP up OK at $(date '+%T') — SSID=$(iw dev "$WLAN" info | awk '/ssid/{print $2}')"
  exit 0
else
  echo "AP FAILED to start — reverting to vuDevices + clearing exit node"
  tailscale set --exit-node=
  nmcli connection up vuDevices
  exit 1
fi
