# Bunker Sandbox - Development Environment with opencode TUI

This repository contains a Docker sandbox for development using opencode TUI, OpenVPN, and Arch Linux.

## Quick Start

### 1. Setup VPN Configuration (Optional)

If you need VPN connectivity:

```bash
# Copy VPN config from Downloads
task vpn:setup

# OR manually:
cp ~/Downloads/YOUR_VPN_SERVER-cli-vpn.l3.ovpn vpn/openvpn.conf

# If VPN requires username/password, create credentials file:
echo -e "your_username\nyour_password" > vpn/credentials
```

### 2. Setup opencode Configuration (Optional)

If you want to use custom opencode settings:

```bash
# Copy opencode config
task config:setup

# Or manually:
cp ~/.config/opencode/opencode.json config/opencode.json
```

### 3. Build the Sandbox

```bash
# Build the Docker image
task sandbox:build
```

### 4. Run the Sandbox

```bash
# Run with VPN (requires vpn/openvpn.conf)
task sandbox:run

# Or run without VPN
task sandbox:run-no-vpn

# For debugging, enter shell directly
task sandbox:shell
```

## Architecture

- **Base**: Arch Linux (via Docker)
- **Packages**: opencode, openvpn, git, bash, fish
- **Dotfiles**: Cloned from https://github.com/iktinoz/dotfiles during build
- **Workspace**: `/home/sandbox`
- **VPN**: Using openvpn with configuration from `vpn/openvpn.conf`

## VPN Features

The container automatically:
- Starts opencode TUI in the background
- Connects VPN using `vpn/openvpn.conf` (if provided)
- Requires `--cap-add=NET_ADMIN` and `--device /dev/net/tun` for VPN
- Cleans up VPN and opencode on exit

## Configuration Files

| File | Description |
|------|-------------|
| `vpn/openvpn.conf` | VPN client configuration (gitignored) |
| `vpn/openvpn.conf.template` | VPN configuration template |
| `vpn/credentials` | VPN username/password (gitignored) |
| `config/opencode.json` | opencode settings (gitignored) |
| `config/opencode.json.template` | opencode settings template |

## Cleanup

```bash
# Remove sandbox image
task sandbox:clean
```

## Publishing Image

To publish the image for public use:

```bash
# Tag and push
docker tag bunker-sandbox <your-registry>/bunker-sandbox:latest
docker push <your-registry>/bunker-sandbox:latest
```

## Notes

- VPN configuration files are `.gitignore`'d to avoid committing sensitive data
- Templates are provided for reference
- Container runs as user `sandbox` (uid 1000)
- All processes are gracefully terminated on exit
