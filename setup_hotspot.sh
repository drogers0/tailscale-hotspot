#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from .env file
if [[ -f "$(dirname "$0")/.env" ]]; then
  source "$(dirname "$0")/.env"
else
  echo "Error: .env file not found in script directory"
  exit 1
fi

### === HELPERS ===
log(){ echo -e "\033[1;32m[+]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[!]\033[0m $*"; }
err(){ echo -e "\033[1;31m[x]\033[0m $*" >&2; }

need_root(){
  if [[ $EUID -ne 0 ]]; then err "Run as root: sudo $0"; exit 1; fi
}
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

nm_safe(){
  # nmcli sometimes fails if connection doesn't exist; ignore those cases
  set +e
  nmcli "$@"
  rc=$?
  set -e
  return $rc
}

iptables_insert_unique() {
  # $1 = table (e.g., nat), $2... = full rule (without -I / -C)
  local table="$1"; shift
  if iptables -t "$table" -C "$@" 2>/dev/null; then
    return 0
  fi
  iptables -t "$table" -I "$@"  # insert at top
}

### === CHECKS ===
need_root

if ! has_cmd nmcli; then err "NetworkManager (nmcli) not found. Install or switch to Raspberry Pi OS with NetworkManager."; exit 1; fi
if ! has_cmd tailscale; then err "tailscale not found. Install via: curl -fsSL https://tailscale.com/install.sh | sh"; exit 1; fi

log "Checking Wi-Fi AP support…"
if ! iw list | awk '/Supported interface modes:/{flag=1;next}/^\s*$/{flag=0}flag' | grep -q '\bAP\b'; then
  err "Your Wi-Fi chipset/driver does not advertise AP mode. Use a compatible USB Wi-Fi or different Pi."
  exit 1
fi
log "AP mode supported."

### === SYSTEM PREP ===
log "Enabling IPv4 forwarding (runtime + persistent)…"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1$' /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

log "Ensuring NetworkManager is active; disabling dhcpcd to avoid conflicts…"
systemctl enable --now NetworkManager >/dev/null 2>&1 || true
systemctl stop dhcpcd >/dev/null 2>&1 || true
systemctl disable dhcpcd >/dev/null 2>&1 || true

log "Setting Wi-Fi regulatory domain to $REG_DOMAIN…"
iw reg set "$REG_DOMAIN" || true

log "Freeing ${WLAN_IF} from any client connection…"
nm_safe device disconnect "$WLAN_IF" >/dev/null 2>&1 || true

### === HOTSPOT CONFIG ===
log "Creating/refreshing NetworkManager AP connection '${HOTSPOT_NAME}'…"
# Delete existing Hotspot to avoid stale settings
nm_safe connection delete "$HOTSPOT_NAME" >/dev/null 2>&1 || true

nmcli connection add type wifi ifname "$WLAN_IF" con-name "$HOTSPOT_NAME" ssid "$SSID" >/dev/null

nmcli connection modify "$HOTSPOT_NAME" \
  802-11-wireless.mode ap \
  802-11-wireless.band "$BAND" \
  802-11-wireless.channel "$CHANNEL" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "$PASS" \
  ipv4.method shared \
  ipv4.addresses "$SUBNET_CIDR" \
  ipv6.method ignore \
  connection.autoconnect no \
  wifi.cloned-mac-address permanent

# If you want to push DNS to clients explicitly, uncomment and customize:
# nmcli connection modify "$HOTSPOT_NAME" ipv4.dns "100.100.100.100 1.1.1.1 9.9.9.9"

### === TAILSCALE EXIT NODE ===
if [[ -n "$EXIT_NODE" ]]; then
  log "Bringing Tailscale up with exit node '$EXIT_NODE'…"
  tailscale up --exit-node="$EXIT_NODE" --exit-node-allow-lan-access=true
else
  warn "EXIT_NODE not set. Skipping 'tailscale up --exit-node=…'. Make sure the Pi is using an exit node."
fi

### === ROUTING/NAT RULES ===
# Extract subnet (e.g., 10.77.0.0/24) from SUBNET_CIDR
SUBNET="$(ipcalc -n "$SUBNET_CIDR" 2>/dev/null | awk -F= '/Network/{print $2}')"
if [[ -z "${SUBNET:-}" ]]; then
  # Fallback calc: crude derivation for /24 only
  if [[ "$SUBNET_CIDR" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/24$ ]]; then
    SUBNET="${BASH_REMATCH[1]}.0/24"
  else
    warn "Could not derive network from $SUBNET_CIDR; defaulting to $SUBNET_CIDR"
    SUBNET="$SUBNET_CIDR"
  fi
fi
log "Using hotspot subnet: $SUBNET"

log "Inserting FORWARD + MASQUERADE rules (idempotent, placed at top)…"
iptables_insert_unique filter FORWARD -i "$WLAN_IF" -o "$TS_DEV" -j ACCEPT
iptables_insert_unique filter FORWARD -i "$TS_DEV" -o "$WLAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables_insert_unique nat POSTROUTING -s "$SUBNET" -o "$TS_DEV" -j MASQUERADE

### === START HOTSPOT ===
log "Bringing hotspot up…"
nmcli connection up "$HOTSPOT_NAME" >/dev/null

log "Hotspot '${SSID}' should now be active on ${WLAN_IF} with subnet ${SUBNET_CIDR}."
log "Clients will egress via Tailscale (${TS_DEV}); ensure the Pi is using your exit node."

### === OPTIONAL PERSISTENCE ===
if [[ "$PERSIST_RULES" == "yes" ]]; then
  if ! dpkg -s netfilter-persistent >/dev/null 2>&1; then
    log "Installing netfilter-persistent to save firewall rules…"
    apt-get update -y >/dev/null
    apt-get install -y netfilter-persistent >/dev/null
  fi
  log "Saving firewall rules…"
  netfilter-persistent save >/dev/null
fi

### === SUMMARY ===
log "Done!"
echo
echo "Summary:"
echo "  SSID:          $SSID"
echo "  Subnet:        $SUBNET_CIDR"
echo "  Exit node:     ${EXIT_NODE:-'(not set in script)'}"
echo "  Hotspot name:  $HOTSPOT_NAME"
echo
echo "Verification tips:"
echo "  * On the Pi:   curl -4 ifconfig.me   # should show your exit node's public IP"
echo "  * On a client: visit https://ifconfig.me (after joining the SSID) — same exit node IP"
