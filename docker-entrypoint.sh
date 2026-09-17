#!/bin/bash
set -e

trap cleanup SIGTERM SIGINT

cleanup() {
  echo "Cleaning up..."
  pkill -f openvpn 2>/dev/null || true
  exit 0
}

# Start VPN if config exists (SKIP_VPN=1 forces a VPN-less start even when the
# image was built with a client.conf, e.g. for `task claude:login`)
if [ -f /etc/openvpn/client.conf ] && [ -z "$SKIP_VPN" ]; then
  VPN_STATUS="Enabled"
  echo "Starting VPN connection..."
  echo -n "VPN username: "
  read -r VPN_USER
  echo -n "VPN password: "
  read -rs VPN_PASS
  echo

  CREDS_FILE=$(mktemp)
  printf '%s\n%s\n' "$VPN_USER" "$VPN_PASS" > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"

  openvpn --config /etc/openvpn/client.conf --auth-user-pass "$CREDS_FILE" >> /tmp/openvpn.log 2>&1 &

  # Wipe credentials from disk once openvpn has read them
  sleep 2 && rm -f "$CREDS_FILE" &
elif [ -n "$SKIP_VPN" ] && [ -f /etc/openvpn/client.conf ]; then
  VPN_STATUS="Skipped (SKIP_VPN=1)"
  echo "SKIP_VPN set, starting without VPN..."
else
  VPN_STATUS="Not configured"
  echo "No VPN config found, starting without VPN..."
fi

# Sync image-managed Claude Code config into the persistent volume mounted at
# $CLAUDE_CONFIG_DIR. A named volume is seeded from the image only when it is first
# created, so these paths are re-copied on every start.
#
# The list is a whitelist for two reasons: it never touches .credentials.json,
# .claude.json, projects/ or history, and removing each path before copying lets a
# deletion in the dotfiles actually reach the volume. Never `rm -rf "$CLAUDE_DIR"`
# itself - the login lives there.
#
# The sandbox's own memory and setting overrides are not synced at all. They live in
# the image at /etc/claude-code/, Claude Code's managed-policy layer.
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-/home/sandbox/.claude}
mkdir -p "$CLAUDE_DIR"
for p in settings.json CLAUDE.md statusline-command.sh arbeit-arbeit.mp3 hooks; do
  rm -rf "$CLAUDE_DIR/$p"
  if [ -e "/opt/bunker/claude/$p" ]; then
    cp -a "/opt/bunker/claude/$p" "$CLAUDE_DIR/$p"
  fi
done
chown -R sandbox "$CLAUDE_DIR"
chgrp -R sandbox "$CLAUDE_DIR"

if [ -f "$CLAUDE_DIR/.credentials.json" ]; then
  CLAUDE_STATUS="Logged in"
else
  CLAUDE_STATUS="Not logged in - run 'claude' and use /login"
fi

# opencode's config holds {env:OFFIS_LITELLM_API_KEY}, substituted when it parses the
# file. An unset variable yields an empty apiKey and an opaque 401 at the first
# request, so say it here instead.
if [ -n "$OFFIS_LITELLM_API_KEY" ]; then
  OPENCODE_STATUS="API key present"
else
  OPENCODE_STATUS="OFFIS_LITELLM_API_KEY unset - pass it with 'docker run -e', or opencode cannot reach the OFFIS provider"
fi

echo ""
echo "Sandbox is ready!"
echo "  - VPN: $VPN_STATUS"
echo "  - Claude Code: $CLAUDE_STATUS"
echo "  - opencode: $OPENCODE_STATUS"
echo ""

# `su -` resets the environment, which would drop the API key passed in with
# `docker run -e`. `-w` keeps that one variable. Do not inline the value into the
# `-c` string instead: that would expose it in /proc/*/cmdline.
SU_KEEP="-w OFFIS_LITELLM_API_KEY"

if [ "$#" -gt 0 ]; then
  # re-quote so multi-word arguments survive the trip through `su -c`
  CMD=$(printf '%q ' "$@")
  if [ -n "$ENTRY_DIR" ]; then
    exec su $SU_KEEP -s /bin/bash - sandbox -c "cd '$ENTRY_DIR' && exec $CMD"
  else
    exec su $SU_KEEP -s /bin/bash - sandbox -c "exec $CMD"
  fi
elif [ -n "$ENTRY_DIR" ]; then
  exec su $SU_KEEP -s /bin/bash - sandbox -c "cd '$ENTRY_DIR' && exec fish -l"
else
  exec su $SU_KEEP -s /bin/fish - sandbox
fi
