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

# Copy opencode configuration if it exists (optional - run 'task config:setup' first)
COPY config/ /tmp/opencode-config/
RUN if [ -f /tmp/opencode-config/opencode.json ]; then \
      mkdir -p /home/sandbox/.config/opencode && \
      cp /tmp/opencode-config/opencode.json /home/sandbox/.config/opencode/opencode.json && \
      chown sandbox:sandbox /home/sandbox/.config/opencode/opencode.json; \
    fi && rm -rf /tmp/opencode-config

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Entrypoint runs as root so OpenVPN can manage network interfaces;
# the shell is dropped to sandbox user via exec su
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
