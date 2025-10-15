#!/bin/bash
set -euo pipefail

# This script runs inside the container during build to install MCP servers
# It copies MCP Python files from /opt/mcp-source to /opt/codex-home/mcp
# and updates the Codex config.toml accordingly.

MCP_SOURCE="/opt/mcp-source"
MCP_DEST="/opt/codex-home/mcp"
MCP_PYTHON="/opt/mcp-venv/bin/python3"
CONFIG_DIR="/opt/codex-home/.codex"
CONFIG_PATH="${CONFIG_DIR}/config.toml"
HELPER_SCRIPT="${CONFIG_DIR}/update_mcp_config.py"

log() {
  echo "[install_mcp] $*" >&2
}

if [[ ! -d "$MCP_SOURCE" ]]; then
  log "MCP source directory not found at ${MCP_SOURCE}; skipping MCP install."
  exit 0
fi

# Use POSIX globbing for macOS compatibility
shopt -s nullglob 2>/dev/null || true
FILES=("${MCP_SOURCE}"/*.py)
shopt -u nullglob 2>/dev/null || true

if [[ ${#FILES[@]} -eq 0 ]]; then
  log "No MCP server scripts found under ${MCP_SOURCE}; skipping MCP install."
  exit 0
fi

# Filter to ensure they're actual files
FILTERED=()
for src_path in "${FILES[@]}"; do
  if [[ -f "$src_path" ]]; then
    FILTERED+=("$src_path")
  fi
done

if [[ ${#FILTERED[@]} -eq 0 ]]; then
  log "No valid MCP server scripts after filtering; skipping MCP install."
  exit 0
fi

# Sort the files
IFS=$'\n'
SORTED=($(printf '%s\n' "${FILTERED[@]}" | sort))
IFS=$' \t\n'

log "Found ${#SORTED[@]} MCP server script(s):"
for src in "${SORTED[@]}"; do
  log "  - ${src}"
done

# Create all necessary directories
mkdir -p "$MCP_DEST"
mkdir -p "$CONFIG_DIR"

# Copy files and collect basenames
BASENAMES=()
COPIED=0
for src in "${SORTED[@]}"; do
  base="$(basename "$src")"
  log "Copying ${base} to ${MCP_DEST}"
  cp "$src" "${MCP_DEST}/${base}" || {
    log "Error: Failed to copy ${base}"
    exit 1
  }
  chmod 0644 "${MCP_DEST}/${base}" || {
    log "Error: Failed to chmod ${base}"
    exit 1
  }
  BASENAMES+=("$base")
  COPIED=$((COPIED + 1))
  log "Successfully copied ${base}"
done

# Check if helper script exists
if [[ ! -f "$HELPER_SCRIPT" ]]; then
  log "Error: helper script missing at ${HELPER_SCRIPT}"
  exit 1
fi

log "Updating Codex config with ${COPIED} MCP server(s): ${BASENAMES[*]}"

# Update config.toml with MCP servers
"$MCP_PYTHON" "$HELPER_SCRIPT" "$CONFIG_PATH" "$MCP_PYTHON" "${BASENAMES[@]}"

log "Successfully installed ${COPIED} MCP server(s) into ${MCP_DEST}"
