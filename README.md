# Tailscale Hotspot Setup

A simple solution to create a Wi-Fi hotspot on Raspberry Pi that routes all traffic through a Tailscale exit node, providing secure internet access for connected devices.

## Overview

This project allows you to:
- Create a Wi-Fi access point on your Raspberry Pi
- Route all hotspot traffic through a Tailscale exit node
- Provide secure internet access to devices that don't support Tailscale natively
- Bypass network restrictions by using your own exit node

## Prerequisites

- Raspberry Pi with Wi-Fi capability (Pi 3, Pi 4, or Pi Zero W/2W)
- Raspberry Pi OS with NetworkManager (recommended)
- Tailscale account and at least one exit node configured

## Installation

1. **Install Tailscale** (if not already installed):
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   ```
   follow instructions to sign in

2. **Clone this repository**:
   ```bash
   git clone <repository-url>
   cd tailscale-hotspot
   ```

3. **Configure environment variables**:
   ```bash
   cp .env.example .env
   nano .env
   ```

4. **Run the setup script**:
   ```bash
   sudo ./setup_hotspot.sh
   ```

## Configuration

All configuration is done through the `.env` file. The `.env.example` file contains detailed explanations of every configuration option.

**Set your key values**:
   - `EXIT_NODE`: Your Tailscale exit node hostname (find with `tailscale status`)
   - `SSID`: Your Wi-Fi network name
   - `PASS`: Your Wi-Fi password
   - `REG_DOMAIN`: Your country code (US, GB, DE, etc.)

The `.env.example` file includes comprehensive documentation for all options, troubleshooting tips, and security considerations.

## Usage

### First-Time Setup
Run the setup script to configure everything:
```bash
sudo ./setup_hotspot.sh
```

This script will:
- Check system requirements
- Configure IPv4 forwarding
- Set up NetworkManager
- Create the Wi-Fi hotspot configuration
- Configure Tailscale with your exit node
- Set up routing and NAT rules
- Start the hotspot

### Starting/Stopping the Hotspot

After initial setup, use the start script:
```bash
sudo ./start_hotspot.sh
```

To stop the hotspot:
```bash
sudo nmcli connection down Hotspot
```

### Checking Status

**Verify hotspot is running:**
```bash
nmcli connection show --active | grep Hotspot
```

**Check connected clients:**
```bash
iw dev wlan0 station dump
```

**Verify Tailscale exit node:**
```bash
tailscale status
curl -4 ifconfig.me
```

**Test from a connected device:**
- Connect to your Wi-Fi hotspot
- Visit https://ifconfig.me
- The IP should match your exit node's public IP

## Boot Automation & Remote Management

> **Note (deployed setup):** On the live Pi the hotspot is started on every boot by a
> systemd service, with an automatic fallback so a failed start can't lock you out.
> The deployed AP broadcasts SSID **`vuDevice`** and routes clients through the
> Tailscale exit node. There is an important Tailscale gotcha — see below.

### Auto-start on boot (`tailscale-hotspot.service`)

`hotspot-up.sh` (run by `tailscale-hotspot.service`) brings the hotspot up at boot:

1. Enables IPv4 forwarding
2. Sets the Tailscale exit node
3. Re-applies the FORWARD + MASQUERADE iptables rules
4. Brings up the `Hotspot` NetworkManager AP
5. **Self-heal:** if `wlan0` does not come up in AP mode, it reverts to the
   `vuDevices` client connection and clears the exit node, so the Pi stays
   reachable instead of stranded.

Install:

```bash
sudo cp hotspot-up.sh /usr/local/sbin/hotspot-up.sh
sudo chmod +x /usr/local/sbin/hotspot-up.sh
sudo cp tailscale-hotspot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable tailscale-hotspot.service
# The service controls the AP, so stop NetworkManager from auto-joining it:
sudo nmcli connection modify Hotspot connection.autoconnect no
```

### ⚠️ Exit node vs. remote management (important gotcha)

When the Pi uses a Tailscale **exit node**, **inbound connections to the Pi over
Tailscale stop working** — the Pi can reach out, but you cannot SSH *in* over its
`100.x` Tailscale address. This is `tailscaled` behavior (peer→Pi traffic is
dropped while an exit node is active), **not** a routing bug; kernel policy routing
does not fix it. So while the hotspot is running you cannot manage the Pi over
Tailscale.

**To get a shell on the Pi while the hotspot is active:**

- **Join the hotspot Wi-Fi** and `ssh pi@10.77.0.1` (the hotspot gateway), **or**
- **Console** (monitor + keyboard), **or**
- Temporarily restore Tailscale with `sudo tailscale set --exit-node=`
  (this disables client tunneling until the next reboot / service run).

### Verifying tunneling

On the Pi, or on any device joined to the hotspot:

```bash
curl -4 https://ifconfig.me
```

This should show the **exit node's** public IP, not the local uplink's. If it
matches the exit node, client traffic is tunneling correctly.

## Troubleshooting

### Common Issues

**1. "AP mode not supported" error**
- Some Wi-Fi adapters don't support Access Point mode
- Try a different USB Wi-Fi adapter
- Check with: `iw list | grep -A 8 "Supported interface modes"`

**2. Hotspot starts but no internet**
- Verify Tailscale is connected: `tailscale status`
- Check if exit node is online in Tailscale admin console
- Ensure exit node allows subnet routing

**3. Can't connect to hotspot**
- Check if channel is supported: `iw phy phy0 info`
- Try changing channel in `.env` file
- Verify regulatory domain is correct

**4. Conflicts with existing network**
- Change `SUBNET_CIDR` to avoid IP conflicts
- Common alternatives: `192.168.50.1/24`, `172.16.1.1/24`

### Debug Commands

**Check NetworkManager status:**
```bash
systemctl status NetworkManager
nmcli general status
```

**Check iptables rules:**
```bash
sudo iptables -L -n
sudo iptables -t nat -L -n
```

**Monitor logs:**
```bash
journalctl -f -u NetworkManager
```

## How It Works

1. **Wi-Fi Hotspot**: Creates an access point using NetworkManager
2. **DHCP**: NetworkManager provides IP addresses to connected devices
3. **Routing**: iptables rules forward traffic from Wi-Fi to Tailscale
4. **NAT**: MASQUERADE rule translates client IPs for Tailscale
5. **Exit Node**: Tailscale routes all traffic through your specified exit node

## Network Flow

```
Client Device → Wi-Fi Hotspot → Raspberry Pi → Tailscale → Exit Node → Internet
                (wlan0)         (routing)     (tailscale0)   (your server)
```

## Security Considerations

- Change default SSID and password
- Use strong WPA2 passwords (consider WPA3 if supported)
- Regularly update your Raspberry Pi and Tailscale
- Monitor connected devices
- Consider MAC address filtering for additional security

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Search existing GitHub issues
3. Create a new issue with:
   - Your Raspberry Pi model
   - Operating system version
   - Complete error messages
   - Output of `tailscale status`

## Acknowledgments

- [Tailscale](https://tailscale.com) for their mesh VPN solution
- The Raspberry Pi community for hardware and OS support
- NetworkManager developers for reliable network management
