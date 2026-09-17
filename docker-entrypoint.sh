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

# Sync repo-managed Claude Code config into the persistent volume mounted at
# $CLAUDE_CONFIG_DIR. Only these two files are image-managed and overwritten on
# every start; .credentials.json, .claude.json, projects/ and history stay untouched.
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-/home/sandbox/.claude}
mkdir -p "$CLAUDE_DIR"
for f in settings.json CLAUDE.md; do
  if [ -f "/opt/bunker/claude/$f" ]; then
    cp "/opt/bunker/claude/$f" "$CLAUDE_DIR/$f"
  fi
done
chown -R sandbox:sandbox "$CLAUDE_DIR"

if [ -f "$CLAUDE_DIR/.credentials.json" ]; then
  CLAUDE_STATUS="Logged in"
else
  CLAUDE_STATUS="Not logged in - run 'claude' and use /login"
fi

echo ""
echo "Sandbox is ready!"
echo "  - VPN: $VPN_STATUS"
echo "  - Claude Code: $CLAUDE_STATUS"
echo ""

if [ "$#" -gt 0 ]; then
  # re-quote so multi-word arguments survive the trip through `su -c`
  CMD=$(printf '%q ' "$@")
  if [ -n "$ENTRY_DIR" ]; then
    exec su -s /bin/bash - sandbox -c "cd '$ENTRY_DIR' && exec $CMD"
  else
    exec su -s /bin/bash - sandbox -c "exec $CMD"
  fi
elif [ -n "$ENTRY_DIR" ]; then
  exec su -s /bin/bash - sandbox -c "cd '$ENTRY_DIR' && exec fish -l"
else
  exec su -s /bin/fish - sandbox
fi
