#!/bin/bash
# claude-sandbox.sh - spustí Claude Code v Docker sandboxu v aktuálním adresáři
#
# Použití:
#   claude-sandbox              # nová session
#   claude-sandbox -r           # obnovení poslední session
#   claude-sandbox -r <id>      # obnovení konkrétní session
#   claude-sandbox -p "udělej X" # příkaz rovnou
#
# Volitelné env proměnné:
#   CLAUDE_NETWORK=none|host    # default: host
#   CLAUDE_MEMORY=8g            # default: 8g
#   CLAUDE_CPUS=4               # default: 4
#   CLAUDE_GIT=1|0              # default: 1 (git safety net zapnutý)

set -euo pipefail

PROJECT_DIR="$(pwd)"
HOME_DIR="$HOME"
SANDBOX_DATA="$HOME/.claude-sandbox"

# Konfigurace s výchozími hodnotami
NETWORK="${CLAUDE_NETWORK:-host}"
MEMORY="${CLAUDE_MEMORY:-8g}"
CPUS="${CLAUDE_CPUS:-4}"
GIT_ENABLED="${CLAUDE_GIT:-1}"

# Vytvoř lokální adresáře pokud neexistují
mkdir -p ~/.claude ~/.config ~/.local
mkdir -p "$SANDBOX_DATA"/{go,npm,pip,cache}

# Restore .claude.json pokud chybí ale existuje backup
if [ ! -f ~/.claude.json ] && [ -d ~/.claude/backups ]; then
  BACKUP=$(ls -t ~/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
  if [ -n "$BACKUP" ]; then
    cp "$BACKUP" ~/.claude.json
    echo "ℹ️  Obnoven .claude.json z backupu"
  fi
fi

# Vytvoř prázdný .claude.json pokud stále neexistuje
[ ! -f ~/.claude.json ] && echo '{}' > ~/.claude.json

# === Git safety net (volitelný) ===
BACKUP_BRANCH=""
if [ "$GIT_ENABLED" = "1" ]; then
  if [ ! -d "$PROJECT_DIR/.git" ]; then
    echo "📁 Git repo neexistuje — inicializuji..."
    cd "$PROJECT_DIR"
    git init
    git add -A
    git commit -m "init: stav před Claude Code" --allow-empty
  fi

  if [ -d "$PROJECT_DIR/.git" ]; then
    cd "$PROJECT_DIR"
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet HEAD 2>/dev/null; then
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      git stash push -m "claude-sandbox-backup-$TIMESTAMP" --include-untracked
      echo "⚠️  Neuložené změny zastashovány: claude-sandbox-backup-$TIMESTAMP"
      echo "   Obnovení: git stash pop"
    fi
    BACKUP_BRANCH="claude-sandbox-backup/$(date +%Y%m%d_%H%M%S)"
    git branch "$BACKUP_BRANCH" HEAD 2>/dev/null || true
    echo "🔒 Záloha vytvořena: $BACKUP_BRANCH"
    echo "   Návrat: git reset --hard $BACKUP_BRANCH"
  fi
else
  echo "ℹ️  Git safety net vypnutý (CLAUDE_GIT=0)"
fi

# Sestav docker argumenty
DOCKER_ARGS=(
  -it --rm
  --user "$(id -u):$(id -g)"
  -e HOME="$HOME_DIR"
  -e GOPATH="$HOME_DIR/go"
  -e PATH="$HOME_DIR/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  --tmpfs "$HOME_DIR":uid="$(id -u)"

  # Limity zdrojů
  --memory="$MEMORY"
  --cpus="$CPUS"

  # Síť
  --network "$NETWORK"

  # Tmpfs pro dočasné soubory
  --tmpfs /tmp:size=2g
  --tmpfs /var/tmp:size=1g
  --tmpfs /run

  # Claude Code data (sessions, auth, nastavení)
  -v ~/.claude:"$HOME_DIR/.claude"
  -v ~/.claude.json:"$HOME_DIR/.claude.json"
  -v ~/.config:"$HOME_DIR/.config"
  -v ~/.local:"$HOME_DIR/.local"

  # Git
  -v ~/.gitconfig:"$HOME_DIR/.gitconfig":ro

  # Persistentní cache pro balíčky
  -v "$SANDBOX_DATA/go":"$HOME_DIR/go"
  -v "$SANDBOX_DATA/npm":"$HOME_DIR/.npm"
  -v "$SANDBOX_DATA/pip":"$HOME_DIR/.cache/pip"
  -v "$SANDBOX_DATA/cache":"$HOME_DIR/.cache"

  # Projekt - stejná cesta jako na hostu kvůli session historii
  -v "$PROJECT_DIR":"$PROJECT_DIR"
  -w "$PROJECT_DIR"
)

# SSH - připoj klíče a agent pokud existují
if [ -d ~/.ssh ]; then
  DOCKER_ARGS+=(-v ~/.ssh:"$HOME_DIR/.ssh":ro)
  # Known hosts potřebuje zápis
  [ -f ~/.ssh/known_hosts ] && DOCKER_ARGS+=(-v ~/.ssh/known_hosts:"$HOME_DIR/.ssh/known_hosts")
fi
if [ -n "${SSH_AUTH_SOCK:-}" ]; then
  DOCKER_ARGS+=(-v "$SSH_AUTH_SOCK":/tmp/ssh-agent.sock -e SSH_AUTH_SOCK=/tmp/ssh-agent.sock)
fi

GIT_STATUS="zapnutý"
[ "$GIT_ENABLED" != "1" ] && GIT_STATUS="vypnutý"

echo "╔══════════════════════════════════════╗"
echo "║       Claude Code Sandbox            ║"
echo "╠══════════════════════════════════════╣"
echo "║ Projekt:  $PROJECT_DIR"
echo "║ Síť:      $NETWORK"
echo "║ Paměť:    $MEMORY | CPU: $CPUS"
echo "║ Cache:    $SANDBOX_DATA"
echo "║ Git:      $GIT_STATUS"
echo "╚══════════════════════════════════════╝"

docker run "${DOCKER_ARGS[@]}" claude-sandbox "$@"

# === Po skončení: ukáž co Claude změnil ===
if [ "$GIT_ENABLED" = "1" ] && [ -d "$PROJECT_DIR/.git" ]; then
  cd "$PROJECT_DIR"
  CHANGES=$(git diff --stat 2>/dev/null)
  NEW_FILES=$(git ls-files --others --exclude-standard 2>/dev/null)
  if [ -n "$CHANGES" ] || [ -n "$NEW_FILES" ]; then
    echo ""
    echo "📋 Claude provedl tyto změny:"
    echo "─────────────────────────────"
    [ -n "$CHANGES" ] && echo "$CHANGES"
    [ -n "$NEW_FILES" ] && echo -e "\nNové soubory:\n$NEW_FILES"
    echo "─────────────────────────────"
    echo ""
    echo "Co chceš udělat?"
    echo "  1) ✅ Přijmout změny (commit)"
    echo "  2) 👀 Zobrazit detailní diff"
    echo "  3) ↩️  Vrátit vše zpět"
    echo "  4) 🚪 Nechat jak je (rozhodnu se později)"
    echo ""
    read -rp "Volba [1-4]: " choice
    case $choice in
      1)
        echo "🤖 Generuji commit message..."
        SUGGESTED_MSG=$(git diff --stat 2>/dev/null; git diff --cached --stat 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)
        SUGGESTED_MSG=$(echo "$SUGGESTED_MSG" | head -20)
        AUTO_MSG=$(docker run --rm \
          --user "$(id -u):$(id -g)" \
          -e HOME="$HOME_DIR" \
          --tmpfs "$HOME_DIR":uid="$(id -u)" \
          -v ~/.claude:"$HOME_DIR/.claude" \
          -v ~/.claude.json:"$HOME_DIR/.claude.json" \
          -v ~/.config:"$HOME_DIR/.config" \
          --network "$NETWORK" \
          claude-sandbox -p "Vygeneruj POUZE jednořádkovou git commit message (anglicky, max 72 znaků, bez uvozovek) pro tyto změny: $SUGGESTED_MSG" 2>/dev/null | tail -1 || echo "")
        [ -z "$AUTO_MSG" ] && AUTO_MSG="claude changes"
        echo "📝 Návrh: $AUTO_MSG"
        read -rp "Commit message [$AUTO_MSG]: " msg
        msg="${msg:-$AUTO_MSG}"
        git add -A && git commit -m "$msg"
        echo "✅ Změny commitnuty."
        ;;
      2)
        git diff
        git ls-files --others --exclude-standard
        echo ""
        read -rp "Přijmout tyto změny? [a/v/n] (accept/vrátit/nechat): " choice2
        case $choice2 in
          a)
            echo "🤖 Generuji commit message..."
            SUGGESTED_MSG=$(git diff --stat 2>/dev/null | head -20)
            AUTO_MSG=$(docker run --rm \
              --user "$(id -u):$(id -g)" \
              -e HOME="$HOME_DIR" \
              --tmpfs "$HOME_DIR":uid="$(id -u)" \
              -v ~/.claude:"$HOME_DIR/.claude" \
              -v ~/.claude.json:"$HOME_DIR/.claude.json" \
              -v ~/.config:"$HOME_DIR/.config" \
              --network "$NETWORK" \
              claude-sandbox -p "Vygeneruj POUZE jednořádkovou git commit message (anglicky, max 72 znaků, bez uvozovek) pro tyto změny: $SUGGESTED_MSG" 2>/dev/null | tail -1 || echo "")
            [ -z "$AUTO_MSG" ] && AUTO_MSG="claude changes"
            echo "📝 Návrh: $AUTO_MSG"
            read -rp "Commit message [$AUTO_MSG]: " msg
            msg="${msg:-$AUTO_MSG}"
            git add -A && git commit -m "$msg"
            echo "✅ Změny commitnuty."
            ;;
          v)
            git checkout . && git clean -fd
            echo "↩️  Změny vráceny na stav před Claude."
            ;;
          *)
            echo "🚪 Změny ponechány v working directory."
            ;;
        esac
        ;;
      3)
        git checkout . && git clean -fd
        echo "↩️  Změny vráceny na stav před Claude."
        ;;
      *)
        echo "🚪 Změny ponechány v working directory."
        [ -n "$BACKUP_BRANCH" ] && echo "   Záloha: $BACKUP_BRANCH"
        ;;
    esac
  else
    echo ""
    echo "ℹ️  Claude neprovedl žádné změny v souborech."
  fi
fi
