FROM node:24-slim

ARG TZ
ENV TZ="$TZ"

# Install base tooling, add GitHub CLI apt repository, and install developer deps
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg2 \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    aggregate \
    ca-certificates \
    curl \
    dnsutils \
    fzf \
    gh \
    git \
    gnupg2 \
    iproute2 \
    ipset \
    iptables \
    jq \
    less \
    man-db \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    socat \
    unzip \
    ripgrep \
    zsh \
  && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global \
  && chown -R node:node /usr/local/share

# Set up npm global install directory for root and install Codex
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH="${PATH}:/usr/local/share/npm-global/bin"

ARG CODEX_CLI_VERSION=0.42.0
RUN npm install -g @openai/codex@${CODEX_CLI_VERSION} \
  && npm cache clean --force \
  && rm -rf /usr/local/share/npm-global/lib/node_modules/codex-cli/node_modules/.cache \
  && rm -rf /usr/local/share/npm-global/lib/node_modules/codex-cli/tests \
  && rm -rf /usr/local/share/npm-global/lib/node_modules/codex-cli/docs

# Install MCP server dependencies inside a virtual environment to avoid PEP-668 issues
ENV MCP_VENV=/opt/mcp-venv
RUN python3 -m venv "$MCP_VENV" \
  && "$MCP_VENV/bin/pip" install --no-cache-dir --upgrade pip \
  && "$MCP_VENV/bin/pip" install --no-cache-dir aiohttp fastmcp tomlkit
ENV PATH="$MCP_VENV/bin:$PATH"
ENV VIRTUAL_ENV="$MCP_VENV"

# Keep npm on the latest patch level for node 24
RUN npm install -g npm@11.6.1

# Inside the container we consider the environment already sufficiently locked
# down, therefore instruct Codex CLI to allow running without sandboxing.
ENV CODEX_UNSAFE_ALLOW_NO_SANDBOX=1

# Copy and set up firewall script as root.
USER root
COPY scripts/init_firewall.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/init_firewall.sh \
  && chmod 555 /usr/local/bin/init_firewall.sh

# Install Codex entrypoint helper
COPY scripts/codex_entry.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/codex_entry.sh \
  && chmod 555 /usr/local/bin/codex_entry.sh

# Copy login script and convert line endings
COPY scripts/codex_login.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/codex_login.sh \
  && chmod 555 /usr/local/bin/codex_login.sh

# Copy Codex gateway HTTP service
COPY scripts/codex_gateway.js /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/codex_gateway.js \
  && chmod 555 /usr/local/bin/codex_gateway.js

# Copy MCP source files into the image
COPY MCP/ /opt/mcp-source/

# Copy MCP installation script and helper
COPY scripts/install_mcp_servers.sh /opt/
COPY scripts/update_mcp_config.py /opt/codex-home/.codex/
RUN sed -i 's/\r$//' /opt/install_mcp_servers.sh \
  && chmod 555 /opt/install_mcp_servers.sh \
  && chmod 644 /opt/codex-home/.codex/update_mcp_config.py

# Install MCP servers during build
RUN /opt/install_mcp_servers.sh

# Default to running as root so bind mounts succeed on Windows drives with restrictive ACLs.
USER root
