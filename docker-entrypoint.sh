#!/bin/bash
set -e

trap cleanup SIGTERM SIGINT

cleanup() {
  echo "Cleaning up..."
  pkill -f openvpn 2>/dev/null || true
  exit 0
}

# Start VPN if config exists
if [ -f /etc/openvpn/client.conf ]; then
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
else
  echo "No VPN config found, starting without VPN..."
fi

echo ""
echo "Sandbox is ready!"
echo "  - VPN: $([ -f /etc/openvpn/client.conf ] && echo 'Enabled' || echo 'Not configured')"
echo ""

exec su -s /bin/fish - sandbox
