#!/bin/bash
set -e

trap cleanup SIGTERM SIGINT

cleanup() {
  echo "Cleaning up..."
  pkill -f openvpn 2>/dev/null || true
  pkill -f opencode 2>/dev/null || true
  exit 0
}

echo "Starting opencode TUI..."

# Start opencode in background
opencode start &

# Start VPN if config exists
if [ -f /etc/openvpn/client.conf ]; then
  echo "Starting VPN connection..."
  if [ -f /etc/openvpn/credentials ]; then
    openvpn --config /etc/openvpn/client.conf --auth-user-pass /etc/openvpn/credentials &
  else
    openvpn --config /etc/openvpn/client.conf &
  fi
else
  echo "No VPN config found, starting without VPN..."
fi

echo ""
echo "Sandbox is ready!"
echo "  - opencode: Running"
echo "  - VPN: $([ -f /etc/openvpn/client.conf ] && echo 'Enabled' || echo 'Not configured')"
echo ""
echo "Press Ctrl+C to exit"

# Keep container alive
wait
