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
#   CLAUDE_DENY_GIT=1|0          # default: 0 (deny git write operations)
#   CLAUDE_MOUNTS="/data:/data:ro,/mnt/shared:/mnt/shared"
#                               # extra bind mounts (comma-separated)

set -euo pipefail

PROJECT_DIR="$(pwd)"
HOME_DIR="$HOME"
SANDBOX_DATA="$HOME/.claude-sandbox"

# Load saved configuration (env variables still override)
if [ -f "$SANDBOX_DATA/config" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$SANDBOX_DATA/config"
  set +a
fi

# Configuration with defaults (env > config > hardcoded)
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

# === Git safety net: worktree approach ===
WORKTREE_DIR="$PROJECT_DIR/.claude-worktree"
WORKTREE_BRANCH=""

if [ "$GIT_ENABLED" = "1" ]; then
  # Initialize git repo if it doesn't exist
  if [ ! -d "$PROJECT_DIR/.git" ]; then
    echo "📁 Git repo not found — initializing..."
    cd "$PROJECT_DIR"
    git init
    git add -A
    git commit -m "init: state before Claude Code" --allow-empty
  fi

  cd "$PROJECT_DIR"

  # Detect existing worktree
  if [ -d "$WORKTREE_DIR" ]; then
    WORKTREE_BRANCH=$(git -C "$WORKTREE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    echo "📂 Found existing worktree (branch: $WORKTREE_BRANCH)"
    read -rp "   Continue in existing worktree? [Y/n]: " choice
    if [[ "$choice" =~ ^[Nn] ]]; then
      git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
      [ -n "$WORKTREE_BRANCH" ] && git branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
      WORKTREE_BRANCH=""
    fi
  fi

  # Create new worktree if it doesn't exist
  if [ ! -d "$WORKTREE_DIR" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    WORKTREE_BRANCH="claude-sandbox/$TIMESTAMP"
    git worktree add "$WORKTREE_DIR" -b "$WORKTREE_BRANCH"
    echo "🌿 Worktree created: .claude-worktree (branch: $WORKTREE_BRANCH)"
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
  -e CLAUDE_DENY_GIT="${CLAUDE_DENY_GIT:-0}"
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
)

# Project mount: worktree or direct
if [ -d "$WORKTREE_DIR" ]; then
  # Mount worktree in place of project — Claude sees no difference
  DOCKER_ARGS+=(-v "$WORKTREE_DIR":"$PROJECT_DIR" -w "$PROJECT_DIR")
else
  DOCKER_ARGS+=(-v "$PROJECT_DIR":"$PROJECT_DIR" -w "$PROJECT_DIR")
fi

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
DENY_GIT_STATUS="off"
[ "${CLAUDE_DENY_GIT:-0}" = "1" ] && DENY_GIT_STATUS="on"

WORKTREE_INFO=""
[ -n "$WORKTREE_BRANCH" ] && WORKTREE_INFO=" (branch: $WORKTREE_BRANCH)"

echo "╔══════════════════════════════════════╗"
echo "║       Claude Code Sandbox            ║"
echo "╠══════════════════════════════════════╣"
echo "║ Project:  $PROJECT_DIR"
echo "║ Network:  $NETWORK"
echo "║ Memory:   $MEMORY | CPU: $CPUS"
echo "║ Cache:    $SANDBOX_DATA"
echo "║ Git:      $GIT_STATUS"
echo "║ Deny git: $DENY_GIT_STATUS"
[ -n "$WORKTREE_BRANCH" ] && echo "║ Worktree: .claude-worktree$WORKTREE_INFO"
echo "╚══════════════════════════════════════╝"

docker run "${DOCKER_ARGS[@]}" claude-sandbox "$@"

# === After exit: worktree review menu ===
if [ "$GIT_ENABLED" = "1" ] && [ -d "$WORKTREE_DIR" ] && [ -n "$WORKTREE_BRANCH" ]; then
  cd "$PROJECT_DIR"
  MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

  # Check if there are any changes in the worktree branch
  DIFF_STAT=$(git diff --stat "$MAIN_BRANCH"..."$WORKTREE_BRANCH" 2>/dev/null || true)
  COMMIT_COUNT=$(git rev-list --count "$MAIN_BRANCH".."$WORKTREE_BRANCH" 2>/dev/null || echo "0")

  if [ -n "$DIFF_STAT" ] || [ "$COMMIT_COUNT" -gt 0 ] 2>/dev/null; then
    echo ""
    echo "📋 Claude made changes in worktree (branch: $WORKTREE_BRANCH)"
    echo "   $COMMIT_COUNT commit(s)"
    echo "─────────────────────────────"
    [ -n "$DIFF_STAT" ] && echo "$DIFF_STAT"
    echo "─────────────────────────────"
    echo ""

    while true; do
      echo "What would you like to do?"
      echo "  1) 👀 View diff (side-by-side)"
      echo "  2) 📋 Copy changes to project (rsync)"
      echo "  3) 🔀 Merge branch into project"
      echo "  4) 🚪 Keep worktree (continue later)"
      echo "  5) 🗑️  Delete worktree and discard changes"
      echo ""
      read -rp "Choice [1-5]: " choice

      case $choice in
        1)
          # Show diff with delta if available, otherwise plain git diff
          if command -v delta &>/dev/null; then
            git diff "$MAIN_BRANCH"..."$WORKTREE_BRANCH" | delta --side-by-side
          else
            git diff "$MAIN_BRANCH"..."$WORKTREE_BRANCH"
          fi
          echo ""
          # Loop back to menu
          ;;
        2)
          echo "📋 Copying changes from worktree to project..."
          rsync -a --exclude='.git' "$WORKTREE_DIR/" "$PROJECT_DIR/"
          echo "✅ Changes copied to project directory."
          read -rp "   Delete worktree now? [Y/n]: " del_choice
          if [[ ! "$del_choice" =~ ^[Nn] ]]; then
            git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
            git branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
            echo "🗑️  Worktree removed."
          fi
          break
          ;;
        3)
          echo "🔀 Merging branch $WORKTREE_BRANCH into $MAIN_BRANCH..."
          git merge "$WORKTREE_BRANCH" --no-edit
          if [ $? -eq 0 ]; then
            echo "✅ Branch merged successfully."
            read -rp "   Delete worktree now? [Y/n]: " del_choice
            if [[ ! "$del_choice" =~ ^[Nn] ]]; then
              git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
              git branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
              echo "🗑️  Worktree removed."
            fi
          else
            echo "⚠️  Merge conflicts detected. Resolve manually, then remove worktree:"
            echo "   git worktree remove .claude-worktree && git branch -D $WORKTREE_BRANCH"
          fi
          break
          ;;
        4)
          echo "🚪 Worktree preserved at: .claude-worktree"
          echo "   Branch: $WORKTREE_BRANCH"
          echo "   Resume: claude-sandbox -r"
          break
          ;;
        5)
          git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
          git branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
          echo "🗑️  Worktree and branch deleted."
          break
          ;;
        *)
          echo "Invalid choice, please try again."
          ;;
      esac
    done
  else
    echo ""
    echo "ℹ️  Claude made no changes."
    read -rp "   Delete worktree? [Y/n]: " del_choice
    if [[ ! "$del_choice" =~ ^[Nn] ]]; then
      git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
      git branch -D "$WORKTREE_BRANCH" 2>/dev/null || true
      echo "🗑️  Worktree removed."
    fi
  fi
fi
