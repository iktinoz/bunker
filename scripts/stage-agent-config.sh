#!/bin/bash
# Turn the exported dotfiles into the sandbox's agent config. Runs at image build time.
#
# The dotfiles describe the host. Two things must change for the container:
#
#   Claude Code: enabledPlugins and extraKnownMarketplaces have to be removed
#   physically. Managed settings cannot do it - list and object keys are merged across
#   all scopes, never replaced, so a managed file can only add entries. Everything else
#   the sandbox overrides lives in managed-settings.json and /etc/claude-code/CLAUDE.md,
#   which Claude Code layers itself.
#
#   opencode: no policy layer exists, so the overlay is merged here with jq `*`.
#   mcp.gitnexus is dropped rather than nulled, because a null member fails opencode's
#   schema validation instead of being ignored.
#
# Missing or invalid input fails the build. A guarded build would produce a working
# image with silently absent config, which is worse than no image.
set -euo pipefail

DOTFILES=${1:?usage: stage-agent-config.sh <dotfiles-dir> <bunker-config-dir>}
BUNKER=${2:?usage: stage-agent-config.sh <dotfiles-dir> <bunker-config-dir>}

CLAUDE_STAGE=/opt/bunker/claude
OPENCODE_DIR=/home/sandbox/.config/opencode

# Exactly the paths the entrypoint syncs into the volume. Staging a whitelist rather
# than the whole tree keeps Claude Code's own runtime directories - sessions/,
# backups/, downloads/, created by the installer earlier in the build - out of the
# staging area. Keep this list and the entrypoint's loop in sync.
CLAUDE_PATHS=(settings.json CLAUDE.md statusline-command.sh arbeit-arbeit.mp3 hooks)

die() { echo "stage-agent-config: $*" >&2; exit 1; }

[ -d "$DOTFILES/.claude" ] || die "no .claude/ in $DOTFILES - did the git archive export run?"
[ -f "$DOTFILES/.claude/settings.json" ] || die "missing $DOTFILES/.claude/settings.json"
[ -f "$OPENCODE_DIR/opencode.json" ] || die "missing $OPENCODE_DIR/opencode.json"
[ -f "$BUNKER/opencode.sandbox.json" ] || die "missing $BUNKER/opencode.sandbox.json"

# --- Claude Code ------------------------------------------------------------
# hooks, statusline and the notification sound are portable: arbeit-notify.sh looks for
# a player and a notifier at runtime and becomes a silent no-op here, and the other two
# only need jq, which the image installs.
mkdir -p "$CLAUDE_STAGE"
for p in "${CLAUDE_PATHS[@]}"; do
  if [ -e "$DOTFILES/.claude/$p" ]; then
    cp -a "$DOTFILES/.claude/$p" "$CLAUDE_STAGE/$p"
  fi
done

# Never redirect onto the input file: the shell truncates it before jq reads it.
# mktemp is mode 600, so set a readable mode explicitly after the move.
tmp=$(mktemp)
jq --exit-status 'del(.enabledPlugins, .extraKnownMarketplaces)' \
   "$DOTFILES/.claude/settings.json" > "$tmp"
mv "$tmp" "$CLAUDE_STAGE/settings.json"
chmod 0644 "$CLAUDE_STAGE/settings.json"

# --- opencode ---------------------------------------------------------------
tmp=$(mktemp)
jq -s --exit-status '(.[0] | del(.mcp.gitnexus)) * .[1]' \
   "$OPENCODE_DIR/opencode.json" "$BUNKER/opencode.sandbox.json" > "$tmp"
mv "$tmp" "$OPENCODE_DIR/opencode.json"
chmod 0644 "$OPENCODE_DIR/opencode.json"

# --- verify -----------------------------------------------------------------
jq empty "$CLAUDE_STAGE/settings.json" "$OPENCODE_DIR/opencode.json"

jq --exit-status 'has("enabledPlugins") or has("extraKnownMarketplaces") | not' \
   "$CLAUDE_STAGE/settings.json" >/dev/null \
   || die "host-only plugin keys survived the strip"
jq --exit-status '.mcp.gitnexus == null' "$OPENCODE_DIR/opencode.json" >/dev/null \
   || die "mcp.gitnexus survived the strip"
if grep -qE 'sk-[A-Za-z0-9_-]{16,}' "$OPENCODE_DIR/opencode.json"; then
  die "a literal API key reached the image - opencode.json must use {env:...}"
fi

echo "stage-agent-config: staged Claude Code config in $CLAUDE_STAGE"
echo "stage-agent-config: merged opencode config in $OPENCODE_DIR/opencode.json"
