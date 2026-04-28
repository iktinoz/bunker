# Core system
FROM archlinux:latest

# Update package database and install base packages
RUN pacman -Syu --noconfirm

# Install opencode, openvpn, git, and required tools
RUN pacman -S --noconfirm \
    opencode \
    openvpn \
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
RUN useradd -m -u 1000 -s /bin/fish sandbox

# Clone and setup dotfiles
WORKDIR /tmp/dotfiles
RUN git clone https://github.com/iktinoz/dotfiles . && \
    cp -r .config /home/sandbox/ && \
    cp .gitconfig /home/sandbox/ && \
    chown -R sandbox:sandbox /home/sandbox

# Setup directory structure
RUN mkdir -p /etc/openvpn /home/sandbox/.config/openticate

# Copy VPN configuration if exists
COPY vpn/openvpn.conf /etc/openvpn/client.conf 2>/dev/null || true
COPY vpn/credentials /etc/openvpn/credentials 2>/dev/null || true

# Copy opencode configuration if exists
COPY config/opencode.json /home/sandbox/.config/opencode/opencode.json 2>/dev/null || true

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Switch to sandbox user
USER sandbox
WORKDIR /home/sandbox

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
