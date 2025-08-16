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
