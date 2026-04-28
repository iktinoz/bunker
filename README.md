# Bunker Sandbox - Development Environment with opencode TUI

This repository contains a Docker sandbox for development using opencode TUI, OpenVPN, and Arch Linux.

## Quick Start

### 1. Setup VPN Configuration (Optional)

Place your downloaded `.ovpn` file from your company at `vpn/openvpn.ovpn`:

```bash
cp ~/Downloads/your-vpn-config.ovpn vpn/openvpn.ovpn
```

VPN credentials are **never stored on disk** — you will be prompted interactively for username and password each time the container starts.

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
task sandbox:build
```

### 4. Run the Sandbox

```bash
# Run with VPN (requires vpn/openvpn.ovpn)
task sandbox:run

# Or run without VPN
task sandbox:run-no-vpn

# For debugging, enter shell directly
task sandbox:shell
```

When VPN is configured, the container will prompt for credentials at startup:

```
VPN username: <your_username>
VPN password: <your_password>
```

## Architecture

- **Base**: Arch Linux (via Docker)
- **Packages**: opencode, openvpn, git, bash, fish
- **Dotfiles**: Cloned from https://github.com/iktinoz/dotfiles during build
- **Workspace**: `/home/sandbox`
- **VPN**: Using openvpn with configuration from `vpn/openvpn.ovpn`

## VPN Features

The container automatically:
- Starts opencode TUI in the background
- Connects VPN using `vpn/openvpn.ovpn` (if provided), prompting for credentials at startup
- Writes credentials to a temporary file (chmod 600) and wipes it after openvpn reads them
- Requires `--cap-add=NET_ADMIN` and `--device /dev/net/tun` for VPN
- Cleans up VPN and opencode on exit

## Configuration Files

| File | Description |
|------|-------------|
| `vpn/openvpn.ovpn` | VPN client configuration (gitignored) |
| `vpn/openvpn.ovpn.template` | VPN configuration template |
| `config/opencode.json` | opencode settings (gitignored) |
| `config/opencode.json.template` | opencode settings template |

## Cleanup

```bash
task sandbox:clean
```

## Publishing Image

To publish the image for public use:

```bash
docker tag bunker-sandbox <your-registry>/bunker-sandbox:latest
docker push <your-registry>/bunker-sandbox:latest
```

## Notes

- VPN configuration files are `.gitignore`'d to avoid committing sensitive data
- VPN credentials are never stored in the image or on disk — prompted at runtime
- Templates are provided for reference
- Container runs as user `sandbox` (uid 1000)
- All processes are gracefully terminated on exit
