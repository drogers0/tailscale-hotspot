#!/usr/bin/env bash

# Load environment variables from .env file
if [[ -f "$(dirname "$0")/.env" ]]; then
  source "$(dirname "$0")/.env"
else
  echo "Error: .env file not found in script directory"
  exit 1
fi

sudo tailscale up --exit-node="${EXIT_NODE}" --exit-node-allow-lan-access=true
sudo iptables -I FORWARD 1 -i "${WLAN_IF}" -o "${TS_DEV}" -j ACCEPT
sudo iptables -I FORWARD 1 -i "${TS_DEV}" -o "${WLAN_IF}" -m state --state RELATED,ESTABLISHED -j ACCEPT

# Extract subnet from SUBNET_CIDR for the MASQUERADE rule
SUBNET="$(echo "${SUBNET_CIDR}" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\.0/')/$(echo "${SUBNET_CIDR}" | cut -d'/' -f2)"
if [[ "${SUBNET_CIDR}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/24$ ]]; then
  SUBNET="${BASH_REMATCH[1]}.0/24"
else
  # Fallback - use the SUBNET_CIDR as-is if it's already in network format
  SUBNET="${SUBNET_CIDR}"
fi

sudo iptables -t nat -I POSTROUTING 1 -s "${SUBNET}" -o "${TS_DEV}" -j MASQUERADE
sudo nmcli connection up "${HOTSPOT_NAME}"
