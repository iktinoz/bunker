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

# Install opencode, openvpn, git, and required tools.
# jq is not optional: the build-time config staging needs it, and so do the statusline
# and session-banner hooks that come in from the dotfiles.
RUN pacman -S --noconfirm \
    opencode \
    openvpn \
    openresolv \
    git \
    jq \
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

# Personal config comes from the dotfiles repo, which is private. `task sandbox:build`
# exports the tracked paths with `git archive` into .build/dotfiles/ before calling
# docker, so the build needs no credentials, no network and no clone. Docker keys this
# layer on the exported content, so it rebuilds exactly when the dotfiles change.
#
# Copy a whitelist, not all of .config: hypr, waybar, wofi, mako, k9s and nvim target a
# desktop this container does not have.
COPY .build/dotfiles/ /tmp/dotfiles/
RUN cd /tmp/dotfiles && \
    mkdir -p /home/sandbox/.config && \
    cp -a .config/fish /home/sandbox/.config/ && \
    cp -a .config/opencode /home/sandbox/.config/ && \
    cp -a .claude /home/sandbox/.claude && \
    cp .gitconfig /home/sandbox/ && \
    chown -R sandbox /home/sandbox && \
    chgrp -R sandbox /home/sandbox && \
    rm -rf /tmp/dotfiles

# Install Claude Code (not packaged in the Arch repos - official native installer).
# Run via `su -` so HOME is /home/sandbox and the binary lands in the sandbox
# user's ~/.local/bin, then symlink it onto the global PATH.
RUN su -s /bin/bash - sandbox -c 'curl -fsSL https://claude.ai/install.sh | bash' && \
    ln -sf /home/sandbox/.local/bin/claude /usr/local/bin/claude

# Setup directory structure and create the update-resolv-conf script.
# Writes DNS directly to /etc/resolv.conf (resolvconf can't run in Docker —
# no init system, and Docker owns resolv.conf with a signature mismatch).
RUN mkdir -p /etc/openvpn /home/sandbox/.config/openticate && \
    chown -R sandbox /home/sandbox/.config/openticate && \
    chgrp -R sandbox /home/sandbox/.config/openticate && \
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

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Keep all Claude Code state (settings, .credentials.json, .claude.json, history)
# in one directory so a single named volume persists the login across rebuilds.
# The auto-updater is disabled because the binary sits in a root-owned path chain.
# GIT_TERMINAL_PROMPT=0 is a safety belt: the dotfiles' .gitconfig sets core.askpass
# and a glab credential helper, neither of which exists here, so without it a git call
# can block on the TTY that Claude Code owns.
ENV CLAUDE_CONFIG_DIR=/home/sandbox/.claude \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    GIT_TERMINAL_PROMPT=0

# `su -` gives the sandbox user a login shell with a reset environment, so the vars
# above would never reach it. Re-export them as login-shell snippets for both shells
# the user can land in (bash via `su -s /bin/bash`, fish for the default shell).
RUN printf 'export CLAUDE_CONFIG_DIR=%s\nexport DISABLE_AUTOUPDATER=%s\nexport CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=%s\nexport GIT_TERMINAL_PROMPT=%s\n' \
      "$CLAUDE_CONFIG_DIR" "$DISABLE_AUTOUPDATER" "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "$GIT_TERMINAL_PROMPT" \
      > /etc/profile.d/claude-code.sh && \
    chmod 644 /etc/profile.d/claude-code.sh && \
    mkdir -p /etc/fish/conf.d && \
    printf 'set -gx CLAUDE_CONFIG_DIR %s\nset -gx DISABLE_AUTOUPDATER %s\nset -gx CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC %s\nset -gx GIT_TERMINAL_PROMPT %s\n' \
      "$CLAUDE_CONFIG_DIR" "$DISABLE_AUTOUPDATER" "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "$GIT_TERMINAL_PROMPT" \
      > /etc/fish/conf.d/claude-code.fish

# Sandbox-only agent config. This is the last stage on purpose: editing config/ must not
# rebuild the layers above it.
#
# /etc/claude-code/ is Claude Code's managed-policy layer. It loads before the user's own
# settings and memory and cannot be switched off, so bunker states the sandbox facts
# there instead of baking a copy of the personal CLAUDE.md.
#
# opencode has no such layer, so stage-agent-config.sh merges an overlay into its config
# and drops the host-only MCP server. Claude Code's config is only staged under
# /opt/bunker/claude because /home/sandbox/.claude is a persistent volume at runtime -
# the entrypoint syncs it in on every start.
COPY config/ /tmp/bunker-config/
COPY scripts/stage-agent-config.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/stage-agent-config.sh && \
    mkdir -p /etc/claude-code && \
    install -m 0644 /tmp/bunker-config/claude/CLAUDE.md /etc/claude-code/CLAUDE.md && \
    install -m 0644 /tmp/bunker-config/claude/managed-settings.json /etc/claude-code/managed-settings.json && \
    jq empty /etc/claude-code/managed-settings.json && \
    /usr/local/bin/stage-agent-config.sh /home/sandbox /tmp/bunker-config && \
    chown -R sandbox /home/sandbox/.config/opencode /home/sandbox/.claude /opt/bunker && \
    chgrp -R sandbox /home/sandbox/.config/opencode /home/sandbox/.claude /opt/bunker && \
    rm -rf /tmp/bunker-config

# Entrypoint runs as root so OpenVPN can manage network interfaces;
# the shell is dropped to sandbox user via exec su
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
