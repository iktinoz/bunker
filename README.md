# Bunker Sandbox - Development Environment with opencode & Claude Code

This repository contains a Docker sandbox for development using the opencode TUI,
Claude Code, OpenVPN, and Arch Linux.

## Quick Start

### 1. Setup VPN Configuration (Optional)

Place your downloaded `.ovpn` file from your company at `vpn/openvpn.ovpn`:

```bash
cp ~/Downloads/your-vpn-config.ovpn vpn/openvpn.ovpn
```

VPN credentials are **never stored on disk** — you will be prompted interactively for username and password each time the container starts.

### 2. Setup Agent Configuration (Optional)

If you want to use custom opencode settings:

```bash
# Copy opencode config
task config:setup

# Or manually:
cp ~/.config/opencode/opencode.json config/opencode.json
```

If you want to seed Claude Code with your host settings:

```bash
task config:setup:claude
```

This strips the `hooks` and `statusLine` keys, which point at host-only scripts that
don't exist in the image — a missing hook script fails the session on its first
matching tool call. If you skip this step, the tracked
`config/claude/settings.json.template` is baked in instead.

It also copies `~/.claude/CLAUDE.md` if you have one. That file usually describes your
*host* environment, which is not what's inside the container — you may prefer to delete
`config/claude/CLAUDE.md` and let the sandbox-specific
`config/claude/CLAUDE.md.template` be used instead, or hand-write your own.

### 3. Build the Sandbox

```bash
task sandbox:build
```

### 4. Log in to Claude Code (once)

```bash
task claude:login
```

The login is written to the persistent `bunker-claude` Docker volume and survives
image rebuilds, so this is a one-time step. Use `task claude:reset` to wipe it and
start over.

### 5. Run the Sandbox

```bash
# Run with VPN (requires vpn/openvpn.ovpn)
task sandbox:run

# Or run without VPN
task sandbox:run-no-vpn

# Optionally mount a host directory as the entry folder
task sandbox:run -- /path/to/repo

# For debugging, enter shell directly
task sandbox:shell
```

When VPN is configured, the container will prompt for credentials at startup:

```
VPN username: <your_username>
VPN password: <your_password>
```

Inside the sandbox both agents are on `PATH` — run `opencode` or `claude` from the
shell.

## Architecture

- **Base**: Arch Linux (via Docker)
- **Packages**: opencode, openvpn, git, bash, fish
- **Claude Code**: installed with the official native installer (not in the Arch
  repos) into `/home/sandbox/.local/bin`, symlinked to `/usr/local/bin/claude`
- **Dotfiles**: Cloned from https://github.com/iktinoz/dotfiles during build
- **Workspace**: `/home/sandbox`
- **VPN**: Using openvpn with configuration from `vpn/openvpn.ovpn`

## Claude Code State

`CLAUDE_CONFIG_DIR` is set to `/home/sandbox/.claude`, so Claude Code keeps its
settings, `.credentials.json`, `.claude.json` and session history in one directory.
That directory is a named Docker volume (`bunker-claude`) mounted by every run task,
which is what makes the login persist.

Repo-managed files (`settings.json`, `CLAUDE.md`) are staged in the image under
`/opt/bunker/claude/` and re-synced into the volume by the entrypoint on **every**
start — editing `config/claude/` and rebuilding is enough to update them. Everything
else in the volume (credentials, history, project state) is left untouched.

The auto-updater and non-essential traffic are disabled in the image
(`DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`); the binary
lives in a root-owned path chain, so a self-update from the `sandbox` user would fail.

> If the corporate VPN blocks egress to `api.anthropic.com`, run Claude sessions via
> `task sandbox:run-no-vpn`.

## VPN Features

The container automatically:
- Connects VPN using `vpn/openvpn.ovpn` (if provided), prompting for credentials at startup
- Writes credentials to a temporary file (chmod 600) and wipes it after openvpn reads them
- Requires `--cap-add=NET_ADMIN` and `--device /dev/net/tun` for VPN
- Cleans up the VPN connection on exit

`task sandbox:run-no-vpn`, `task sandbox:shell` and `task claude:login` pass
`SKIP_VPN=1`, so they start immediately instead of prompting for VPN credentials even
when `vpn/openvpn.ovpn` was baked into the image.

`opencode` and `claude` are not started automatically — the container drops you into a
fish login shell and you launch whichever agent you want.

## Configuration Files

| File | Description |
|------|-------------|
| `vpn/openvpn.ovpn` | VPN client configuration (gitignored) |
| `vpn/openvpn.ovpn.template` | VPN configuration template |
| `config/opencode.json` | opencode settings (gitignored) |
| `config/opencode.json.template` | opencode settings template |
| `config/tui.json` | opencode TUI theme |
| `config/claude/settings.json` | Claude Code settings (gitignored) |
| `config/claude/settings.json.template` | Claude Code settings template |
| `config/claude/CLAUDE.md` | Claude Code memory for the sandbox (gitignored) |
| `config/claude/CLAUDE.md.template` | Claude Code memory template |

## Cleanup

```bash
task sandbox:clean    # remove the image
task claude:reset     # remove the Claude Code state volume (forces re-login)
```

## Publishing Image

To publish the image for public use:

```bash
docker tag bunker-sandbox <your-registry>/bunker-sandbox:latest
docker push <your-registry>/bunker-sandbox:latest
```

Note that the image contains no credentials — Claude's login lives in the
`bunker-claude` volume, and VPN credentials are prompted at runtime.

## Notes

- VPN and agent configuration files are `.gitignore`'d to avoid committing sensitive data
- VPN credentials are never stored in the image or on disk — prompted at runtime
- Templates are provided for reference
- Container runs the entrypoint as root (OpenVPN needs `NET_ADMIN`) and drops to user `sandbox` (uid 1000) for the shell
- All processes are gracefully terminated on exit
