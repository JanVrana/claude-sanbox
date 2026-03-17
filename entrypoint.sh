#!/bin/bash
set -euo pipefail

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
HOST_USER="${HOST_USER:-claude}"
HOST_HOME="${HOST_HOME:-/home/$HOST_USER}"

# Create group if it doesn't exist
if ! getent group "$HOST_GID" >/dev/null 2>&1; then
  groupadd -g "$HOST_GID" "$HOST_USER"
fi

# Create user or modify existing one (node UID 1000)
EXISTING=$(getent passwd "$HOST_UID" | cut -d: -f1 || true)
if [ -z "$EXISTING" ]; then
  useradd -u "$HOST_UID" -g "$HOST_GID" -d "$HOST_HOME" -s /bin/bash -M "$HOST_USER"
else
  usermod -d "$HOST_HOME" -l "$HOST_USER" "$EXISTING" 2>/dev/null || true
fi

export HOME="$HOST_HOME"
export PATH="$HOST_HOME/.local/bin:$PATH"

# Install bundled slash commands (don't overwrite user's custom ones)
if [ -d /etc/claude-commands ]; then
  mkdir -p "$HOST_HOME/.claude/commands"
  cp -n /etc/claude-commands/*.md "$HOST_HOME/.claude/commands/" 2>/dev/null || true
fi

# Apply default settings if user has no settings.json
if [ ! -f "$HOST_HOME/.claude/settings.json" ] && [ -f /etc/claude-defaults/settings.json ]; then
  mkdir -p "$HOST_HOME/.claude"
  cp /etc/claude-defaults/settings.json "$HOST_HOME/.claude/settings.json"
fi

# Update Claude Code to latest version
echo "Hledají se aktualizace Claude Code..."
npm update -g @anthropic-ai/claude-code 2>/dev/null && echo "Aktualizace dokončena." || echo "Aktualizace se nezdařila, používám stávající verzi."

# Deny git write operations if requested
if [ "${CLAUDE_DENY_GIT:-0}" = "1" ]; then
  SETTINGS_FILE="$HOST_HOME/.claude/settings.json"
  mkdir -p "$HOST_HOME/.claude"
  GIT_DENY='["Bash(git commit:*)","Bash(git push:*)","Bash(git tag:*)","Bash(git branch -d:*)","Bash(git branch -D:*)","Bash(git reset:*)","Bash(git rebase:*)","Bash(git merge:*)","Bash(git cherry-pick:*)","Bash(git revert:*)","Bash(git stash:*)","Bash(git checkout:*)","Bash(git switch:*)","Bash(git restore:*)","Bash(git clean:*)","Bash(git rm:*)","Bash(git mv:*)"]'
  if [ -f "$SETTINGS_FILE" ]; then
    jq --argjson deny "$GIT_DENY" '.permissions.deny = ((.permissions.deny // []) + $deny) | .permissions.deny |= unique' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  else
    echo "{\"permissions\":{\"deny\":$GIT_DENY}}" | jq . > "$SETTINGS_FILE"
  fi
  echo "🔒 Git write operations denied (CLAUDE_DENY_GIT=1)"
fi

exec gosu "$HOST_UID" claude --dangerously-skip-permissions "$@"
