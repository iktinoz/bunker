# bunker

A disposable Arch Linux Docker sandbox for running coding agents — `opencode` and
`claude` (Claude Code) — behind an optional corporate OpenVPN tunnel.

## Never commit

This is a **public** repository. These paths are gitignored and must stay that way:

| Path | Why |
|------|-----|
| `config/opencode.json` | contains a live LLM proxy API key |
| `config/claude/settings.json` | derived from the host's personal settings |
| `config/claude/CLAUDE.md` | derived from the host's personal memory |
| `vpn/openvpn.ovpn` | company VPN profile |

Only the `*.template` counterparts are tracked. Before committing, check
`git status --short --ignored` and make sure those four are still listed as `!!`.
VPN credentials are never stored anywhere — the entrypoint prompts for them at runtime.

## Layout

```
Dockerfile             image: Arch + opencode (pacman) + Claude Code (native installer)
docker-entrypoint.sh   PID 1: starts VPN, syncs Claude config, drops to `sandbox`
Taskfile.yml           all orchestration (go-task); there is no compose file
config/                agent config baked into the image at build time
vpn/                   OpenVPN profile
```

## Commands

```bash
task sandbox:build           # build the image
task claude:login            # one-time Claude Code OAuth, stored in the volume
task sandbox:run -- /repo    # run with VPN, mounting /repo 1:1 as the entry folder
task sandbox:run-no-vpn      # run without VPN
task sandbox:shell           # debug shell
task config:setup            # import host opencode config
task config:setup:claude     # import host Claude config (hooks/statusLine stripped)
```

The binary is `go-task`; `task` is a shell alias on the maintainer's host.

## Things that will bite you

- **The entrypoint runs as root.** OpenVPN needs `NET_ADMIN` to manage `tun0`, so there
  is no `USER` directive; the shell is dropped to `sandbox` (uid 1000) via `exec su` at
  the very end.
- **`su -` resets the environment.** Dockerfile `ENV` vars do *not* survive into the
  sandbox user's shell. Anything the agents need is re-exported from
  `/etc/profile.d/claude-code.sh` and `/etc/fish/conf.d/claude-code.fish`, both
  generated from those same `ENV` values at build time. Add new vars in all three places.
- **`su` wants its options before the username** — `su -s /bin/bash - sandbox`, not
  `su - sandbox -s /bin/bash` (the latter passes `-s` to the login shell).
- **`/home/sandbox/.claude` is a named volume** (`bunker-claude`) holding Claude Code's
  login and history. A named volume is seeded from the image only when first created, so
  repo-managed files are staged at `/opt/bunker/claude/` and re-copied by the entrypoint
  on every start. Never bake credentials into the image.
- **The image may contain `/etc/openvpn/client.conf`.** Any task that must not block on
  the interactive VPN prompt passes `SKIP_VPN=1`.
- **Nothing is auto-started.** The container drops into a fish login shell; you launch
  `opencode` or `claude` yourself.
- **The filesystem is ephemeral** (`docker run --rm`). Only the bind-mounted entry
  folder and the `bunker-claude` volume survive.
- **Config is baked in at build time**, so editing anything under `config/` requires
  `task sandbox:build` before it takes effect.
