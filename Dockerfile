# Core system
FROM archlinux:latest

# Bootstrap keyring: disable sig checks to update archlinux-keyring first,
# then re-enable and run the full system upgrade with trusted keys.
RUN sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf && \
    pacman -Sy --noconfirm archlinux-keyring && \
    sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm

# Install opencode, openvpn, git, and required tools
RUN pacman -S --noconfirm \
    opencode \
    openvpn \
    openresolv \
    git \
    bash \
    fish \
    coreutils \
    sudo \
    iproute2 \
    iputils \
    curl \
    openssh \
    nano

# Create sandbox user with uid 1000
# Also create 'nogroup' group expected by OpenVPN configs (absent on Arch Linux)
RUN groupadd -r nogroup && \
    useradd -m -u 1000 -s /bin/fish sandbox

# Clone and setup dotfiles
WORKDIR /tmp/dotfiles
RUN git clone https://github.com/iktinoz/dotfiles . && \
    cp -r .config /home/sandbox/ && \
    cp .gitconfig /home/sandbox/ && \
    chown -R sandbox:sandbox /home/sandbox

# Install Claude Code (not packaged in the Arch repos - official native installer).
# Run via `su -` so HOME is /home/sandbox and the binary lands in the sandbox
# user's ~/.local/bin, then symlink it onto the global PATH.
RUN su -s /bin/bash - sandbox -c 'curl -fsSL https://claude.ai/install.sh | bash' && \
    ln -sf /home/sandbox/.local/bin/claude /usr/local/bin/claude

# Setup directory structure and create the update-resolv-conf script.
# Writes DNS directly to /etc/resolv.conf (resolvconf can't run in Docker —
# no init system, and Docker owns resolv.conf with a signature mismatch).
RUN mkdir -p /etc/openvpn /home/sandbox/.config/openticate && \
    printf '%s\n' \
      '#!/bin/bash' \
      'case $script_type in' \
      '  up)' \
      '    NMSRVRS=""' \
      '    SRCHDMNS=""' \
      '    for opt in ${!foreign_option_*}; do' \
      '      val="${!opt}"' \
      '      echo "$val" | grep -q "dhcp-option DNS"    && NMSRVRS="$NMSRVRS $(echo "$val" | cut -d" " -f3)"' \
      '      echo "$val" | grep -q "dhcp-option DOMAIN" && SRCHDMNS="$SRCHDMNS $(echo "$val" | cut -d" " -f3)"' \
      '    done' \
      '    cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true' \
      '    { [ -n "$SRCHDMNS" ] && echo "search $SRCHDMNS"; for ns in $NMSRVRS; do echo "nameserver $ns"; done; } > /etc/resolv.conf' \
      '    ;;' \
      '  down)' \
      '    mv /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true' \
      '    ;;' \
      'esac' \
    > /etc/openvpn/update-resolv-conf && \
    chmod +x /etc/openvpn/update-resolv-conf

# Copy VPN configuration if it exists, and add DNS update hooks
COPY vpn/ /tmp/vpn/
RUN if [ -f /tmp/vpn/openvpn.ovpn ]; then \
      cp /tmp/vpn/openvpn.ovpn /etc/openvpn/client.conf && \
      printf '\nscript-security 2\nup /etc/openvpn/update-resolv-conf\ndown /etc/openvpn/update-resolv-conf\n' >> /etc/openvpn/client.conf; \
    fi && rm -rf /tmp/vpn

# Copy agent configuration if it exists (optional - run 'task config:setup' first).
# opencode config is baked straight into its config dir; Claude Code config is only
# staged under /opt/bunker/claude because /home/sandbox/.claude is a persistent
# volume at runtime - the entrypoint syncs it in on every start.
COPY config/ /tmp/bunker-config/
RUN mkdir -p /home/sandbox/.config/opencode && \
    if [ -f /tmp/bunker-config/opencode.json ]; then \
      cp /tmp/bunker-config/opencode.json /home/sandbox/.config/opencode/opencode.json; \
    fi && \
    if [ -f /tmp/bunker-config/tui.json ]; then \
      cp /tmp/bunker-config/tui.json /home/sandbox/.config/opencode/tui.json; \
    fi && \
    chown -R sandbox:sandbox /home/sandbox/.config/opencode && \
    mkdir -p /opt/bunker/claude && \
    for f in settings.json CLAUDE.md; do \
      if [ -f "/tmp/bunker-config/claude/$f" ]; then \
        cp "/tmp/bunker-config/claude/$f" "/opt/bunker/claude/$f"; \
      elif [ -f "/tmp/bunker-config/claude/$f.template" ]; then \
        cp "/tmp/bunker-config/claude/$f.template" "/opt/bunker/claude/$f"; \
      fi; \
    done && \
    mkdir -p /home/sandbox/.claude && \
    chown sandbox:sandbox /home/sandbox/.claude && \
    rm -rf /tmp/bunker-config

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Keep all Claude Code state (settings, .credentials.json, .claude.json, history)
# in one directory so a single named volume persists the login across rebuilds.
# The auto-updater is disabled because the binary sits in a root-owned path chain.
ENV CLAUDE_CONFIG_DIR=/home/sandbox/.claude \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# `su -` gives the sandbox user a login shell with a reset environment, so the vars
# above would never reach it. Re-export them as login-shell snippets for both shells
# the user can land in (bash via `su -s /bin/bash`, fish for the default shell).
RUN printf 'export CLAUDE_CONFIG_DIR=%s\nexport DISABLE_AUTOUPDATER=%s\nexport CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\n' \
      "$CLAUDE_CONFIG_DIR" "$DISABLE_AUTOUPDATER" "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" \
      > /etc/profile.d/claude-code.sh && \
    chmod 644 /etc/profile.d/claude-code.sh && \
    mkdir -p /etc/fish/conf.d && \
    printf 'set -gx CLAUDE_CONFIG_DIR %s\nset -gx DISABLE_AUTOUPDATER %s\nset -gx CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC %s\n' \
      "$CLAUDE_CONFIG_DIR" "$DISABLE_AUTOUPDATER" "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" \
      > /etc/fish/conf.d/claude-code.fish

# Entrypoint runs as root so OpenVPN can manage network interfaces;
# the shell is dropped to sandbox user via exec su
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
