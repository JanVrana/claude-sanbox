#!/bin/bash
# claude-sandbox.sh - runs Claude Code in a Docker sandbox in the current directory
#
# Usage:
#   claude-sandbox              # new session
#   claude-sandbox -r           # resume last session
#   claude-sandbox -r <id>      # resume specific session
#   claude-sandbox -p "do X"    # run a prompt directly
#
# Optional env variables:
#   CLAUDE_NETWORK=none|host    # default: host
#   CLAUDE_MEMORY=8g            # default: 8g
#   CLAUDE_CPUS=4               # default: 4
#   CLAUDE_GIT=1|0              # default: 1 (git safety net enabled)
#   CLAUDE_MOUNTS="/data:/data:ro,/mnt/shared:/mnt/shared"
#                               # extra bind mounts (comma-separated)

set -euo pipefail

PROJECT_DIR="$(pwd)"
HOME_DIR="$HOME"
SANDBOX_DATA="$HOME/.claude-sandbox"

# Configuration with defaults
NETWORK="${CLAUDE_NETWORK:-host}"
MEMORY="${CLAUDE_MEMORY:-8g}"
CPUS="${CLAUDE_CPUS:-4}"
GIT_ENABLED="${CLAUDE_GIT:-1}"

# Create local directories if they don't exist
mkdir -p ~/.claude ~/.config ~/.local
mkdir -p "$SANDBOX_DATA"/{go,npm,pip,cache}

# Restore .claude.json if missing but backup exists
if [ ! -f ~/.claude.json ] && [ -d ~/.claude/backups ]; then
  BACKUP=$(ls -t ~/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
  if [ -n "$BACKUP" ]; then
    cp "$BACKUP" ~/.claude.json
    echo "ℹ️  Restored .claude.json from backup"
  fi
fi

# Create empty .claude.json if it still doesn't exist
[ ! -f ~/.claude.json ] && echo '{}' > ~/.claude.json

# === Git safety net (optional) ===
BACKUP_BRANCH=""
if [ "$GIT_ENABLED" = "1" ]; then
  if [ ! -d "$PROJECT_DIR/.git" ]; then
    echo "📁 Git repo not found — initializing..."
    cd "$PROJECT_DIR"
    git init
    git add -A
    git commit -m "init: state before Claude Code" --allow-empty
  fi

  if [ -d "$PROJECT_DIR/.git" ]; then
    cd "$PROJECT_DIR"
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      git stash push -m "claude-sandbox-backup-$TIMESTAMP" --include-untracked
      echo "⚠️  Unsaved changes stashed: claude-sandbox-backup-$TIMESTAMP"
      echo "   Restore: git stash pop"
    fi
    BACKUP_BRANCH="claude-sandbox-backup/$(date +%Y%m%d_%H%M%S)"
    git branch "$BACKUP_BRANCH" HEAD 2>/dev/null || true
    echo "🔒 Backup created: $BACKUP_BRANCH"
    echo "   Revert: git reset --hard $BACKUP_BRANCH"
  fi
else
  echo "ℹ️  Git safety net disabled (CLAUDE_GIT=0)"
fi

# Build docker arguments
DOCKER_ARGS=(
  -it --rm
  -e HOST_UID="$(id -u)"
  -e HOST_GID="$(id -g)"
  -e HOST_USER="$(id -un)"
  -e HOST_HOME="$HOME_DIR"
  -e GOPATH="$HOME_DIR/go"
  -e PATH="$HOME_DIR/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  --tmpfs "$HOME_DIR":uid="$(id -u)"

  # Resource limits
  --memory="$MEMORY"
  --cpus="$CPUS"

  # Network
  --network "$NETWORK"

  # Tmpfs for temporary files
  --tmpfs /tmp:size=2g
  --tmpfs /var/tmp:size=1g
  --tmpfs /run

  # Claude Code data (sessions, auth, settings)
  -v ~/.claude:"$HOME_DIR/.claude"
  -v ~/.claude.json:"$HOME_DIR/.claude.json"
  -v ~/.config:"$HOME_DIR/.config"
  -v ~/.local:"$HOME_DIR/.local"

  # Git
  -v ~/.gitconfig:"$HOME_DIR/.gitconfig":ro

  # Persistent package cache
  -v "$SANDBOX_DATA/go":"$HOME_DIR/go"
  -v "$SANDBOX_DATA/npm":"$HOME_DIR/.npm"
  -v "$SANDBOX_DATA/pip":"$HOME_DIR/.cache/pip"
  -v "$SANDBOX_DATA/cache":"$HOME_DIR/.cache"

  # Project - same path as on host for session history consistency
  -v "$PROJECT_DIR":"$PROJECT_DIR"
  -w "$PROJECT_DIR"

)

# Extra user-defined mounts (comma-separated, e.g. "/data:/data:ro,/mnt:/mnt")
if [ -n "${CLAUDE_MOUNTS:-}" ]; then
  IFS=',' read -ra MOUNTS <<< "$CLAUDE_MOUNTS"
  for mount in "${MOUNTS[@]}"; do
    mount="$(echo "$mount" | xargs)"  # trim whitespace
    [ -n "$mount" ] && DOCKER_ARGS+=(-v "$mount")
  done
fi

# SSH - mount keys and agent if available
if [ -d ~/.ssh ]; then
  DOCKER_ARGS+=(-v ~/.ssh:"$HOME_DIR/.ssh":ro)
  # Known hosts needs write access
  [ -f ~/.ssh/known_hosts ] && DOCKER_ARGS+=(-v ~/.ssh/known_hosts:"$HOME_DIR/.ssh/known_hosts")
fi
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
  DOCKER_ARGS+=(-v "$SSH_AUTH_SOCK":/tmp/ssh-agent.sock -e SSH_AUTH_SOCK=/tmp/ssh-agent.sock)
fi

GIT_STATUS="enabled"
[ "$GIT_ENABLED" != "1" ] && GIT_STATUS="disabled"

echo "╔══════════════════════════════════════╗"
echo "║       Claude Code Sandbox            ║"
echo "╠══════════════════════════════════════╣"
echo "║ Project:  $PROJECT_DIR"
echo "║ Network:  $NETWORK"
echo "║ Memory:   $MEMORY | CPU: $CPUS"
echo "║ Cache:    $SANDBOX_DATA"
echo "║ Git:      $GIT_STATUS"
echo "╚══════════════════════════════════════╝"

docker run "${DOCKER_ARGS[@]}" claude-sandbox "$@"

# === After exit: show what Claude changed ===
if [ "$GIT_ENABLED" = "1" ] && [ -d "$PROJECT_DIR/.git" ]; then
  cd "$PROJECT_DIR"
  CHANGES=$(git diff --stat 2>/dev/null)
  NEW_FILES=$(git ls-files --others --exclude-standard 2>/dev/null)
  if [ -n "$CHANGES" ] || [ -n "$NEW_FILES" ]; then
    echo ""
    echo "📋 Claude made the following changes:"
    echo "─────────────────────────────"
    [ -n "$CHANGES" ] && echo "$CHANGES"
    [ -n "$NEW_FILES" ] && echo -e "\nNew files:\n$NEW_FILES"
    echo "─────────────────────────────"
    echo ""
    echo "What would you like to do?"
    echo "  1) ✅ Accept changes (commit)"
    echo "  2) 👀 Show detailed diff"
    echo "  3) ↩️  Revert all changes"
    echo "  4) 🚪 Leave as is (decide later)"
    echo ""
    read -rp "Choice [1-4]: " choice
    case $choice in
      1)
        echo "🤖 Generating commit message..."
        SUGGESTED_MSG=$(git diff --stat 2>/dev/null; git diff --cached --stat 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
        SUGGESTED_MSG=$(echo "$SUGGESTED_MSG" | head -20)
        AUTO_MSG=$(docker run --rm \
          -e HOST_UID="$(id -u)" \
          -e HOST_GID="$(id -g)" \
          -e HOST_USER="$(id -un)" \
          -e HOST_HOME="$HOME_DIR" \
          --tmpfs "$HOME_DIR":uid="$(id -u)" \
          -v ~/.claude:"$HOME_DIR/.claude" \
          -v ~/.claude.json:"$HOME_DIR/.claude.json" \
          -v ~/.config:"$HOME_DIR/.config" \
          --network "$NETWORK" \
          claude-sandbox -p "Generate ONLY a one-line git commit message (English, max 72 chars, no quotes) for these changes: $SUGGESTED_MSG" 2>/dev/null | tail -1 || echo "")
        [ -z "$AUTO_MSG" ] && AUTO_MSG="claude changes"
        echo "📝 Suggested: $AUTO_MSG"
        read -rp "Commit message [$AUTO_MSG]: " msg
        msg="${msg:-$AUTO_MSG}"
        git add -A && git commit -m "$msg"
        echo "✅ Changes committed."
        ;;
      2)
        git diff
        git ls-files --others --exclude-standard
        echo ""
        read -rp "Accept these changes? [a/r/l] (accept/revert/leave): " choice2
        case $choice2 in
          a)
            echo "🤖 Generating commit message..."
            SUGGESTED_MSG=$(git diff --stat 2>/dev/null | head -20)
            AUTO_MSG=$(docker run --rm \
              -e HOST_UID="$(id -u)" \
              -e HOST_GID="$(id -g)" \
              -e HOST_USER="$(id -un)" \
              -e HOST_HOME="$HOME_DIR" \
              --tmpfs "$HOME_DIR":uid="$(id -u)" \
              -v ~/.claude:"$HOME_DIR/.claude" \
              -v ~/.claude.json:"$HOME_DIR/.claude.json" \
              -v ~/.config:"$HOME_DIR/.config" \
              --network "$NETWORK" \
              claude-sandbox -p "Generate ONLY a one-line git commit message (English, max 72 chars, no quotes) for these changes: $SUGGESTED_MSG" 2>/dev/null | tail -1 || echo "")
            [ -z "$AUTO_MSG" ] && AUTO_MSG="claude changes"
            echo "📝 Suggested: $AUTO_MSG"
            read -rp "Commit message [$AUTO_MSG]: " msg
            msg="${msg:-$AUTO_MSG}"
            git add -A && git commit -m "$msg"
            echo "✅ Changes committed."
            ;;
          r)
            git checkout . && git clean -fd
            echo "↩️  Changes reverted to pre-Claude state."
            ;;
          *)
            echo "🚪 Changes left in working directory."
            ;;
        esac
        ;;
      3)
        git checkout . && git clean -fd
        echo "↩️  Changes reverted to pre-Claude state."
        ;;
      *)
        echo "🚪 Changes left in working directory."
        [ -n "$BACKUP_BRANCH" ] && echo "   Backup: $BACKUP_BRANCH"
        ;;
    esac
  else
    echo ""
    echo "ℹ️  Claude made no file changes."
  fi
fi
