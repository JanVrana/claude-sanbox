# Claude Code Sandbox

[🇨🇿 Česká verze](README.cs.md)

A Docker sandbox for running Claude Code CLI without confirmation prompts, with optional git safety net to protect your project from unwanted changes.

## Features

- Runs Claude Code in an isolated Docker container
- Skips all confirmation dialogs (`--dangerously-skip-permissions`)
- Optional git safety net — auto-backup before start, interactive review after finish
- Persists authentication, sessions, SSH keys, and package caches between runs
- Pre-installed Go, Node.js, TypeScript, and common development tools
- Shared network — access dev servers from host browser

## Requirements

- Docker
- Claude Code authenticated on host (`claude` → complete OAuth flow)
- Git (optional, for safety net)
- SSH agent (optional, for git push)

## Installation

### 1. Add yourself to the docker group

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Build the Docker image (once)

```bash
cd claude-sandbox/
docker build -t claude-sandbox .
```

### 3. Install the launcher script

```bash
chmod +x claude-sandbox.sh
sudo cp claude-sandbox.sh /usr/local/bin/claude-sandbox
```

### 4. Authenticate Claude Code (once)

```bash
# On the host, not inside the container
npm i -g @anthropic-ai/claude-code
claude
# Complete OAuth in your browser
# You can exit Claude on the host afterwards
```

## Usage

Navigate to your project directory and run:

```bash
cd /path/to/project
claude-sandbox
```

### Common scenarios

```bash
# New session
claude-sandbox

# Resume last session
claude-sandbox -r

# Resume specific session
claude-sandbox -r <session_id>

# Run a prompt directly
claude-sandbox -p "create a REST API for user management"
```

### Configuration via environment variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_NETWORK` | `host` | Network mode: `host` (shared), `none` (offline) |
| `CLAUDE_MEMORY` | `8g` | Container RAM limit |
| `CLAUDE_CPUS` | `4` | Container CPU limit |
| `CLAUDE_GIT` | `1` | Git safety net: `1` enabled, `0` disabled |
| `CLAUDE_MOUNTS` | _(empty)_ | Extra bind mounts, comma-separated (see below) |

```bash
# Fully offline sandbox
CLAUDE_NETWORK=none claude-sandbox

# More resources for heavy builds
CLAUDE_MEMORY=16g CLAUDE_CPUS=5 claude-sandbox

# Skip git safety net
CLAUDE_GIT=0 claude-sandbox

# Combine options
CLAUDE_GIT=0 CLAUDE_NETWORK=none CLAUDE_MEMORY=4g claude-sandbox
```

### Mounting custom directories

By default, only the current project directory is mounted into the container. Use `CLAUDE_MOUNTS` to make additional host directories available — for example shared data, reference repos, or datasets.

```bash
# Mount a single directory (read-only)
CLAUDE_MOUNTS="/data/shared:/data/shared:ro" claude-sandbox

# Mount multiple directories (comma-separated)
CLAUDE_MOUNTS="/data/datasets:/data/datasets:ro,/mnt/reference:/mnt/reference:ro" claude-sandbox

# Read-write mount (use with caution — Claude can modify files)
CLAUDE_MOUNTS="/data/output:/data/output" claude-sandbox
```

Each entry follows the standard Docker bind-mount syntax: `host_path:container_path[:options]`. Use `:ro` for read-only access whenever possible to prevent unintended modifications.

### Changing defaults

Edit the defaults directly in `claude-sandbox.sh`:

```bash
NETWORK="${CLAUDE_NETWORK:-host}"
MEMORY="${CLAUDE_MEMORY:-8g}"
CPUS="${CLAUDE_CPUS:-4}"
GIT_ENABLED="${CLAUDE_GIT:-1}"
```

The value after `:-` is the default, which can be overridden by the environment variable.

## Git Safety Net

When enabled (`CLAUDE_GIT=1`, default):

**Before Claude starts:**
- Initializes a git repo if one doesn't exist
- Stashes uncommitted changes
- Creates a backup branch `claude-sandbox-backup/<timestamp>`

**After Claude finishes:**
- Shows a summary of all changes Claude made
- Presents an interactive menu:
  1. **Accept** — commit changes (with AI-generated commit message)
  2. **View diff** — inspect changes in detail, then accept/revert
  3. **Revert all** — discard all changes
  4. **Leave as-is** — keep changes in working directory for manual review

**Manual rollback at any time:**

```bash
# Reset to backup
git reset --hard claude-sandbox-backup/<timestamp>

# Restore stashed changes
git stash pop
```

## Web Development

With `--network host` (default), Claude can start dev servers accessible from your host browser:

```bash
claude-sandbox -p "create a React app and start the dev server"
# → open http://localhost:3000 in your browser
```

## SSH and GitHub

To enable git push/pull over SSH, start the SSH agent on your host:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

The sandbox automatically forwards the SSH agent into the container.

## What's Inside the Container

- **Node.js 20** + npm, pnpm, yarn
- **Go 1.23.6** + gopls, delve, goimports, golangci-lint
- **TypeScript**, ts-node, ESLint, Prettier, nodemon
- **Python 3** + pip
- Git, curl, wget, jq, build-essential

## Persistent Data

The following data is preserved between runs:

| Data | Host location |
|---|---|
| Claude sessions & auth | `~/.claude/`, `~/.claude.json` |
| Settings | `~/.config/`, `~/.local/` |
| Go modules & tools | `~/.claude-sandbox/go/` |
| npm cache | `~/.claude-sandbox/npm/` |
| pip cache | `~/.claude-sandbox/pip/` |

### Reset all caches

```bash
rm -rf ~/.claude-sandbox
```

## Troubleshooting

**Permission denied on Docker socket:**

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Claude can't access SSH keys:**

Make sure the SSH agent is running: `echo $SSH_AUTH_SOCK`

**`.claude.json` not found error:**

The script automatically restores from backup or creates an empty config. If the issue persists, re-authenticate on the host: `claude`

**Wrong file permissions in project:**

The container runs under your UID/GID, so permissions should match. If not, check with `ls -la` in your project directory.

## File Structure

```
claude-sandbox/
├── Dockerfile           # Docker image with dev tools
├── claude-sandbox.sh    # Launcher script
└── README.cs.md         # Documentation (Czech)
```

## License

MIT
