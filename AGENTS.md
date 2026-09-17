# bunker

A disposable Arch Linux Docker sandbox for running coding agents — `opencode` and
`claude` (Claude Code) — behind an optional corporate OpenVPN tunnel.

## Where config comes from

Personal agent config is **not** kept here. It lives in the maintainer's private
dotfiles repo (`~/.dotfiles`, a bare repo with `$HOME` as its work tree). bunker holds
only the overlay that is true inside the container and nowhere else.

`task sandbox:build` runs `git archive` against that bare repo and unpacks the tracked
paths into `.build/dotfiles/` before calling `docker build`. That needs no credentials,
no network and no clone, which matters because the dotfiles repo is private. Only
committed state is exported, so **commit your dotfiles before you build**. A path that
is not tracked aborts the export rather than shipping a config-less image.

The split:

| Lives in the dotfiles | Lives in bunker |
|---|---|
| `.claude/` — memory, settings, hooks, statusline | `config/claude/CLAUDE.md` — the sandbox facts |
| `.config/opencode/` — `opencode.json`, `tui.json` | `config/claude/managed-settings.json` |
| `.config/fish/`, `.gitconfig` | `config/opencode.sandbox.json` — opencode overlay |

`/etc/claude-code/` is Claude Code's managed-policy layer. It loads before the user's
own settings and memory and cannot be switched off, so bunker states the sandbox facts
there instead of baking a copy of the personal `CLAUDE.md`. Managed settings can only
**add** — list and object keys merge across all scopes — so anything that must be
*removed* is stripped with `jq` in `scripts/stage-agent-config.sh`. Today that is
`enabledPlugins` and `extraKnownMarketplaces`, whose marketplace lives on
`gitlab.offis.de` and has no credential helper in the container.

opencode has no managed layer, so the same script merges `config/opencode.sandbox.json`
over the exported `opencode.json` and drops the host-only `mcp.gitnexus`.

Use `task config:preview` to see exactly what a build would stage, without building.

## Never commit

This is a **public** repository. These paths are gitignored and must stay that way:

| Path | Why |
|------|-----|
| `vpn/openvpn.ovpn` | company VPN profile |
| `vpn/credentials` | never written, but guarded anyway |

Only the `*.template` counterpart is tracked. This is enforced by a gitleaks pre-commit
hook (`.pre-commit-config.yaml` + `.gitleaks.toml`): run `task hooks:install` once per
clone to activate it, and `task hooks:audit` to sweep the full commit history. The
defaults do not cover the VPN profile's static key, so `.gitleaks.toml` adds path rules
for the paths above — keep it in sync if that table changes. If gitleaks flags something
genuinely safe, add a trailing `# gitleaks:allow` or an allowlist entry in
`.gitleaks.toml`; never reach for `git commit --no-verify`.

VPN credentials are never stored anywhere — the entrypoint prompts for them at runtime.
The opencode API key is never stored here either: `opencode.json` holds
`{env:OFFIS_LITELLM_API_KEY}` and the value is passed in at `docker run` time, so it
never enters an image layer.

## Layout

```
Dockerfile             image: Arch + opencode (pacman) + Claude Code (native installer)
docker-entrypoint.sh   PID 1: starts VPN, syncs Claude config, drops to `sandbox`
Taskfile.yml           all orchestration (go-task); there is no compose file
config/                sandbox-only overlay, baked into the image at build time
scripts/               stage-agent-config.sh, run during the build
vpn/                   OpenVPN profile
.build/                gitignored; the exported dotfiles the build copies from
```

## Commands

```bash
task sandbox:build           # export the dotfiles, then build the image
task config:preview          # show what a build would stage, without building
task claude:login            # one-time Claude Code OAuth, stored in the volume
task sandbox:run -- /repo    # run with VPN, mounting /repo 1:1 as the entry folder
task sandbox:run-no-vpn      # run without VPN
task sandbox:shell           # debug shell
task hooks:install           # activate the gitleaks pre-commit hook (once per clone)
task hooks:audit             # scan the full commit history for secrets
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
- **A variable passed in with `docker run -e` needs `su -w`.** `ENV` vars have the
  profile snippets above, but a *runtime* value has nothing to be re-exported from, so
  `su -` simply drops it. The entrypoint keeps `OFFIS_LITELLM_API_KEY` with
  `su -w OFFIS_LITELLM_API_KEY`. Never inline a secret into the `su -c` string instead —
  that exposes it in `/proc/*/cmdline`.
- **`su` wants its options before the username** — `su -s /bin/bash - sandbox`, not
  `su - sandbox -s /bin/bash` (the latter passes `-s` to the login shell).
- **`/home/sandbox/.claude` is a named volume** (`bunker-claude`) holding Claude Code's
  login and history. A named volume is seeded from the image only when first created, so
  image-managed files are staged at `/opt/bunker/claude/` and re-copied by the entrypoint
  on every start. The entrypoint's sync list is a whitelist that it removes before
  copying, so a deletion in the dotfiles propagates; it never touches
  `.credentials.json`, `.claude.json`, `projects/` or history. Never bake credentials
  into the image.
- **`jq` is load-bearing.** The build-time staging needs it, and so do the statusline
  and session-banner hooks that arrive from the dotfiles. Without it the statusline
  prints an error on every render.
- **`GIT_TERMINAL_PROMPT=0` is a safety belt.** The dotfiles' `.gitconfig` sets
  `core.askpass` and a `glab` credential helper; neither binary exists in the image, so
  a git call against a private remote could otherwise block on the TTY that Claude Code
  owns.
- **`jq … "$FILE" > "$FILE"` truncates the file** before jq reads it. The staging script
  writes through `mktemp` + `mv` for that reason.
- **The image may contain `/etc/openvpn/client.conf`.** Any task that must not block on
  the interactive VPN prompt passes `SKIP_VPN=1`.
- **Nothing is auto-started.** The container drops into a fish login shell; you launch
  `opencode` or `claude` yourself.
- **The filesystem is ephemeral** (`docker run --rm`). Only the bind-mounted entry
  folder and the `bunker-claude` volume survive.
- **Config is baked in at build time**, so editing anything under `config/` — or
  committing a dotfiles change — requires `task sandbox:build` before it takes effect.
- **opencode installs its provider SDK on first launch.** `@ai-sdk/openai-compatible` is
  fetched from the npm registry inside the container, which needs egress the corporate
  VPN may block. `task sandbox:run-no-vpn` is the workaround for that first run.
