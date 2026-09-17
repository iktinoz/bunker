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

### 2. Provide the opencode API key

The opencode config reads its LLM proxy key from the environment, so the key is never
stored in this repo or baked into the image:

```jsonc
// in the dotfiles' .config/opencode/opencode.json
"options": { "baseURL": "https://openai.lcl.offis.de", "apiKey": "{env:OFFIS_LITELLM_API_KEY}" }
```

Export `OFFIS_LITELLM_API_KEY` in the shell you run `task` from; every run task passes
it through with `docker run -e`. Without it the container still starts and `claude`
works normally — only opencode's OFFIS provider fails, and the startup banner says so.

### 3. Agent configuration

There is nothing to set up. Personal agent config comes from the maintainer's private
dotfiles repo, which `task sandbox:build` exports with `git archive` before building.
Only committed state is exported, so **commit your dotfiles before you build**.

bunker adds only the sandbox overlay:

| File | Becomes | Purpose |
|------|---------|---------|
| `config/claude/CLAUDE.md` | `/etc/claude-code/CLAUDE.md` | what is true inside the container |
| `config/claude/managed-settings.json` | `/etc/claude-code/managed-settings.json` | sandbox setting overrides |
| `config/opencode.sandbox.json` | merged into `opencode.json` | opencode has no managed layer |

`/etc/claude-code/` is Claude Code's managed-policy layer: it loads before your own
settings and memory and cannot be switched off. So your personal `CLAUDE.md` arrives
unchanged and the sandbox facts are stated alongside it, rather than bunker keeping a
copy of your memory.

Two host-only keys are stripped from `settings.json` during the build:
`enabledPlugins` and `extraKnownMarketplaces`. Their marketplace lives on
`gitlab.offis.de` and the container has no credential helper for it, so the install
would fail. Your `hooks` and `statusLine` are kept — the scripts detect their
dependencies at runtime and work in the container.

Run `task config:preview` to see exactly what a build would stage, without building.

### 4. Build the Sandbox

```bash
task sandbox:build
```

### 5. Log in to Claude Code (once)

```bash
task claude:login
```

The login is written to the persistent `bunker-claude` Docker volume and survives
image rebuilds, so this is a one-time step. Use `task claude:reset` to wipe it and
start over.

### 6. Run the Sandbox

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
- **Packages**: opencode, openvpn, git, jq, bash, fish
- **Claude Code**: installed with the official native installer (not in the Arch
  repos) into `/home/sandbox/.local/bin`, symlinked to `/usr/local/bin/claude`
- **Dotfiles**: exported from the local bare repo `~/.dotfiles` with `git archive`
  before the build, then `COPY`'d in. The repo is private, so the build deliberately
  needs no credentials and no network for this step. A whitelist is copied — `fish`,
  `opencode`, `.claude` and `.gitconfig` — because the rest targets a desktop the
  container does not have.
- **Workspace**: `/home/sandbox`
- **VPN**: Using openvpn with configuration from `vpn/openvpn.ovpn`

## Claude Code State

`CLAUDE_CONFIG_DIR` is set to `/home/sandbox/.claude`, so Claude Code keeps its
settings, `.credentials.json`, `.claude.json` and session history in one directory.
That directory is a named Docker volume (`bunker-claude`) mounted by every run task,
which is what makes the login persist.

Image-managed files — `settings.json`, `CLAUDE.md`, `statusline-command.sh`,
`hooks/` and the notification sound — are staged under `/opt/bunker/claude/` and
re-synced into the volume by the entrypoint on **every** start. The sync list is a
whitelist that the entrypoint removes before copying, so deleting a file in the
dotfiles actually removes it from the volume. Everything else (credentials, history,
project state) is left untouched.

The sandbox's own memory and setting overrides are not synced at all: they live in the
image at `/etc/claude-code/`, Claude Code's managed-policy layer, which loads before
the user layer and cannot be switched off.

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
| `config/claude/CLAUDE.md` | sandbox memory, installed as `/etc/claude-code/CLAUDE.md` |
| `config/claude/managed-settings.json` | sandbox setting overrides, installed as `/etc/claude-code/managed-settings.json` |
| `config/opencode.sandbox.json` | overlay merged over the dotfiles' `opencode.json` |
| `scripts/stage-agent-config.sh` | does the merging and stripping during the build |

Everything personal — `settings.json`, `CLAUDE.md`, hooks, the statusline,
`opencode.json`, `tui.json` — lives in the dotfiles repo, not here.

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
`bunker-claude` volume, VPN credentials are prompted at runtime, and the opencode API
key is read from the environment at container start. It does, however, contain the
maintainer's personal agent config from the dotfiles repo, so a published image is not
suitable for someone else.

## Notes

- The VPN profile is `.gitignore`'d to avoid committing sensitive data; a template is
  provided for reference
- VPN credentials are never stored in the image or on disk — prompted at runtime
- The opencode API key is never stored in this repo or in an image layer — the config
  holds `{env:OFFIS_LITELLM_API_KEY}` and the value arrives via `docker run -e`
- Personal agent config is not kept here; it comes from the private dotfiles repo at
  build time, so commit your dotfiles before you build
- Container runs the entrypoint as root (OpenVPN needs `NET_ADMIN`) and drops to user `sandbox` (uid 1000) for the shell
- All processes are gracefully terminated on exit
