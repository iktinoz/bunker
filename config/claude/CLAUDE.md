# Bunker sandbox

You are running inside the `bunker` Docker sandbox, not on the host. Where another
instruction file describes a host machine — Ceph, a Kubernetes context, the OFFIS
GitLab marketplace, host-only paths — this file describes the machine you are actually
running on. Prefer the facts here.

## The machine

- Arch Linux container, user `sandbox` (uid 1000), login shell fish.
- The filesystem is **ephemeral** — the container runs with `--rm`. Two things survive:
  the host directory bind-mounted at the path you were started in (`$ENTRY_DIR`), and
  `~/.claude`, a named Docker volume holding your login and session history.
- Anything written outside those two locations is lost when the container exits.
- `opencode` is installed alongside you and shares this sandbox.
- An OpenVPN tunnel may be active. If network calls fail, check the tunnel's routes and
  DNS first (`/tmp/openvpn.log`).
- There is no systemd and no host access.

## What is not installed here

`kubectl`, `helm` and `flux` are not installed and no Kubernetes context exists, so the
Ceph guardrail cannot trigger. The `dip-guardrails` plugin is not installed either, so
no `PreToolUse` hook enforces the git-commit confirmation. Ask before you commit anyway.

The `dip-agents` plugin is not installed. The subagents `scout`, `Explore` and
`implementer` do not exist here. Do the work in the main session rather than trying to
delegate it.

The `dip-paper-writing` plugin is not installed, so its skills and the
`source-verifier` agent are unavailable.

All three are absent because their marketplace lives on `gitlab.offis.de` and this
container has no credential helper for it. This is deliberate, not a broken install —
do not try to add the marketplace or install the plugins.
