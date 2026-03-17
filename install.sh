#!/bin/bash
# install.sh - One-liner installer for Claude Code Sandbox
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/JanVrana/claude-sanbox/main/install.sh | bash
#
# Or locally:
#   ./install.sh

set -euo pipefail

REPO_URL="https://github.com/JanVrana/claude-sanbox.git"
INSTALL_DIR="$HOME/.claude-sandbox/repo"
IMAGE_NAME="claude-sandbox"
LAUNCHER_NAME="claude-sandbox"

# --- Colors and helpers ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Read from terminal even when piped (curl | bash)
prompt() { read -rp "$1" "$2" </dev/tty; }

# --- Detect OS ---

OS="$(uname -s)"
case "$OS" in
  Linux)  PLATFORM="linux" ;;
  Darwin) PLATFORM="macos" ;;
  *)      err "Unsupported OS: $OS"; exit 1 ;;
esac

info "Detected platform: $PLATFORM"

# --- 1. Check dependencies ---

if ! command -v git &>/dev/null; then
  err "Git is not installed. Please install git first."
  exit 1
fi
ok "Git found: $(git --version)"

if ! command -v docker &>/dev/null; then
  err "Docker is not installed. Please install Docker first."
  if [ "$PLATFORM" = "macos" ]; then
    echo "  → https://docs.docker.com/desktop/install/mac-install/"
  else
    echo "  → https://docs.docker.com/engine/install/"
  fi
  exit 1
fi
ok "Docker found: $(docker --version)"

# Check Docker is running
if ! docker info &>/dev/null; then
  err "Docker daemon is not running."
  if [ "$PLATFORM" = "macos" ]; then
    echo "  → Start Docker Desktop from Applications."
  else
    echo "  → Try: sudo systemctl start docker"
  fi
  exit 1
fi
ok "Docker daemon is running."

# --- 2. Linux: check docker group membership ---

if [ "$PLATFORM" = "linux" ]; then
  if ! groups | grep -qw docker; then
    warn "Your user is not in the 'docker' group."
    echo "  This may require running docker with sudo."
    prompt "  Add $USER to docker group now? [Y/n]: " choice
    if [[ ! "$choice" =~ ^[Nn] ]]; then
      sudo usermod -aG docker "$USER"
      ok "Added $USER to docker group. You may need to log out and back in."
    fi
  fi
fi

# --- 3. Clone or update repo ---

info "Setting up repository in $INSTALL_DIR ..."

if [ -d "$INSTALL_DIR/.git" ]; then
  info "Repository already exists, pulling latest changes..."
  git -C "$INSTALL_DIR" pull --ff-only
  ok "Repository updated."
else
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
  ok "Repository cloned."
fi

# --- 4. Build Docker image ---

info "Building Docker image '$IMAGE_NAME' (this may take a few minutes)..."
docker build -t "$IMAGE_NAME" "$INSTALL_DIR"
ok "Docker image '$IMAGE_NAME' built successfully."

# --- 5. Install launcher ---

LAUNCHER_SRC="$INSTALL_DIR/claude-sandbox.sh"

if [ ! -f "$LAUNCHER_SRC" ]; then
  err "Launcher script not found at $LAUNCHER_SRC"
  exit 1
fi

INSTALL_TARGET="/usr/local/bin/$LAUNCHER_NAME"

info "Installing launcher to $INSTALL_TARGET ..."

if [ -w "/usr/local/bin" ]; then
  install -m 755 "$LAUNCHER_SRC" "$INSTALL_TARGET"
else
  sudo install -m 755 "$LAUNCHER_SRC" "$INSTALL_TARGET"
fi

ok "Launcher installed: $INSTALL_TARGET"

# --- 6. Verify ---

if command -v "$LAUNCHER_NAME" &>/dev/null; then
  ok "$LAUNCHER_NAME is available in PATH."
else
  # /usr/local/bin is standard on Linux/macOS but may be missing from PATH
  if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    warn "/usr/local/bin is not in your PATH."
    SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
    case "$SHELL_NAME" in
      zsh)  RC_FILE="$HOME/.zshrc" ;;
      bash) RC_FILE="$HOME/.bashrc" ;;
      *)    RC_FILE="$HOME/.profile" ;;
    esac
    EXPORT_LINE='export PATH="/usr/local/bin:$PATH"'
    if [ -f "$RC_FILE" ] && grep -qF '/usr/local/bin' "$RC_FILE"; then
      warn "Found /usr/local/bin reference in $RC_FILE but it's not active. Restart your shell."
    else
      prompt "  Add /usr/local/bin to PATH in $RC_FILE? [Y/n]: " choice
      if [[ ! "$choice" =~ ^[Nn] ]]; then
        echo "" >> "$RC_FILE"
        echo "# Added by claude-sandbox installer" >> "$RC_FILE"
        echo "$EXPORT_LINE" >> "$RC_FILE"
        ok "Added to $RC_FILE. Run: source $RC_FILE"
      else
        warn "Add manually: $EXPORT_LINE"
      fi
    fi
  else
    warn "$LAUNCHER_NAME not found in PATH. You may need to restart your shell."
  fi
fi

# --- 7. Interactive configuration ---

CONFIG_FILE="$HOME/.claude-sandbox/config"

configure_sandbox() {
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "║         Configuration                        ║"
  echo "╠══════════════════════════════════════════════╣"
  echo "║  Set defaults for claude-sandbox.            ║"
  echo "║  You can change these anytime by editing:    ║"
  echo "║  ~/.claude-sandbox/config                    ║"
  echo "║  Or override per-run with env variables.     ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""

  # Load existing values if config exists
  local cfg_network="host"
  local cfg_memory="8g"
  local cfg_cpus="4"
  local cfg_git="1"
  local cfg_deny_git="0"
  local cfg_mounts=""

  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" 2>/dev/null || true
    cfg_network="${CLAUDE_NETWORK:-$cfg_network}"
    cfg_memory="${CLAUDE_MEMORY:-$cfg_memory}"
    cfg_cpus="${CLAUDE_CPUS:-$cfg_cpus}"
    cfg_git="${CLAUDE_GIT:-$cfg_git}"
    cfg_deny_git="${CLAUDE_DENY_GIT:-$cfg_deny_git}"
    cfg_mounts="${CLAUDE_MOUNTS:-$cfg_mounts}"
  fi

  # --- Network ---
  echo "  1) Network mode"
  echo "     host  = shared network, dev servers accessible from browser"
  echo "     none  = fully offline, maximum isolation"
  echo ""
  prompt "     Network mode [host/none] (current: $cfg_network): " input
  cfg_network="${input:-$cfg_network}"

  # --- Memory ---
  echo ""
  echo "  2) Memory limit"
  echo "     How much RAM the container can use (e.g. 4g, 8g, 16g)"
  echo ""
  prompt "     Memory limit (current: $cfg_memory): " input
  cfg_memory="${input:-$cfg_memory}"

  # --- CPUs ---
  echo ""
  echo "  3) CPU limit"
  echo "     Number of CPU cores for the container"
  echo ""
  prompt "     CPU cores (current: $cfg_cpus): " input
  cfg_cpus="${input:-$cfg_cpus}"

  # --- Git safety net ---
  echo ""
  echo "  4) Git safety net (worktree)"
  echo "     1 = Claude works in an isolated worktree, your project stays untouched"
  echo "     0 = Claude edits your project directly"
  echo ""
  prompt "     Git safety net [1/0] (current: $cfg_git): " input
  cfg_git="${input:-$cfg_git}"

  # --- Deny git writes ---
  echo ""
  echo "  5) Deny git write operations"
  echo "     1 = block commit, push, reset etc. inside container"
  echo "     0 = allow all git operations"
  echo ""
  prompt "     Deny git writes [1/0] (current: $cfg_deny_git): " input
  cfg_deny_git="${input:-$cfg_deny_git}"

  # --- Extra mounts ---
  echo ""
  echo "  6) Extra bind mounts (optional)"
  echo "     Comma-separated, e.g.: /data/shared:/data/shared:ro,/mnt:/mnt"
  echo "     Leave empty for none."
  echo ""
  prompt "     Extra mounts (current: ${cfg_mounts:-none}): " input
  cfg_mounts="${input:-$cfg_mounts}"

  # --- Write config ---
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat > "$CONFIG_FILE" <<CONF
# Claude Code Sandbox configuration
# Generated by install.sh — edit freely
# These are sourced as defaults; env variables override them at runtime.

CLAUDE_NETWORK="$cfg_network"
CLAUDE_MEMORY="$cfg_memory"
CLAUDE_CPUS="$cfg_cpus"
CLAUDE_GIT="$cfg_git"
CLAUDE_DENY_GIT="$cfg_deny_git"
CLAUDE_MOUNTS="$cfg_mounts"
CONF

  echo ""
  ok "Configuration saved to $CONFIG_FILE"

  # --- Summary ---
  echo ""
  echo "  ┌────────────────────────────────────┐"
  echo "  │  Network:       $cfg_network"
  echo "  │  Memory:        $cfg_memory"
  echo "  │  CPUs:          $cfg_cpus"
  echo "  │  Git safety:    $([ "$cfg_git" = "1" ] && echo "enabled" || echo "disabled")"
  echo "  │  Deny git:      $([ "$cfg_deny_git" = "1" ] && echo "yes" || echo "no")"
  echo "  │  Extra mounts:  ${cfg_mounts:-none}"
  echo "  └────────────────────────────────────┘"
}

# Ask user if they want to configure
echo ""
prompt "Configure sandbox defaults now? [Y/n]: " do_config
if [[ ! "$do_config" =~ ^[Nn] ]]; then
  configure_sandbox
else
  info "Skipped. You can configure later by running: claude-sandbox --configure"
  info "Or edit ~/.claude-sandbox/config manually."
fi

# --- 8. Auth reminder & finish ---

echo ""
echo "════════════════════════════════════════════"
echo "  Claude Code Sandbox installed!"
echo "════════════════════════════════════════════"
echo ""

if [ -f "$HOME/.claude.json" ]; then
  ok "Claude authentication found (~/.claude.json)."
else
  warn "Claude authentication not found."
  echo ""
  echo "  To authenticate, run on the host:"
  echo "    npm i -g @anthropic-ai/claude-code"
  echo "    claude"
  echo "  Complete OAuth in your browser, then you can exit."
fi

echo ""
echo "  Usage:"
echo "    cd /path/to/project"
echo "    $LAUNCHER_NAME"
echo ""
echo "  Reconfigure anytime:"
echo "    Edit ~/.claude-sandbox/config"
echo ""
