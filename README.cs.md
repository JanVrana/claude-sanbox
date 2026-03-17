# Claude Code Sandbox

[🇬🇧 English version](README.md)

Docker sandbox pro Claude Code — plnohodnotné CLI rozhraní bez otravných potvrzovacích dialogů, s ochranou projektu přes git safety net.

## Co to dělá

- Spustí Claude Code v izolovaném Docker kontejneru
- Automaticky přeskočí potvrzovací dialogy (`--dangerously-skip-permissions`)
- Volitelně vytvoří git zálohu před startem, po skončení ukáže změny a nabídne přijetí/vrácení
- Sdílí přihlášení, sessions, SSH klíče a cache balíčků mezi spuštěními
- Obsahuje Go, Node.js, TypeScript a běžné vývojářské nástroje

## Požadavky

- Docker
- Přihlášený Claude Code na hostitelském systému (`claude` → projít OAuth)
- Git (volitelné, pro safety net)
- SSH agent (volitelné, pro git push)

## Instalace

### 1. Přidej se do skupiny docker (bez sudo)

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Buildni Docker image (jednou)

```bash
cd claude-sandbox/
docker build -t claude-sandbox .
```

### 3. Nainstaluj script

```bash
chmod +x claude-sandbox.sh
sudo cp claude-sandbox.sh /usr/local/bin/claude-sandbox
```

### 4. Přihlaš se do Claude Code (jednou)

```bash
# Na hostu, ne v kontejneru
npm i -g @anthropic-ai/claude-code
claude
# Projdi OAuth přihlášení v prohlížeči
# Pak můžeš Claude na hostu ukončit
```

## Použití

Přejdi do složky projektu a spusť:

```bash
cd /cesta/k/projektu
claude-sandbox
```

### Běžné scénáře

```bash
# Nová session
claude-sandbox

# Obnovení poslední session
claude-sandbox -r

# Obnovení konkrétní session
claude-sandbox -r <session_id>

# Rovnou zadat příkaz
claude-sandbox -p "vytvoř REST API pro správu uživatelů"
```

### Konfigurace přes env proměnné

| Proměnná | Výchozí | Popis |
|---|---|---|
| `CLAUDE_NETWORK` | `host` | Síťový režim: `host` (sdílená síť), `none` (bez sítě) |
| `CLAUDE_MEMORY` | `8g` | Limit RAM pro kontejner |
| `CLAUDE_CPUS` | `4` | Limit CPU jader |
| `CLAUDE_GIT` | `1` | Git safety net: `1` zapnuto, `0` vypnuto |
| `CLAUDE_DENY_GIT` | `0` | Zakáže git zápisy v kontejneru: `1` zakázat, `0` povolit |
| `CLAUDE_MOUNTS` | _(prázdné)_ | Extra bind mounty, oddělené čárkou (viz níže) |

```bash
# Bez sítě (úplný sandbox)
CLAUDE_NETWORK=none claude-sandbox

# Víc zdrojů pro náročný build
CLAUDE_MEMORY=16g CLAUDE_CPUS=5 claude-sandbox

# Bez git zálohy
CLAUDE_GIT=0 claude-sandbox

# Zakázat git zápisy (commit, push, reset, atd.)
CLAUDE_DENY_GIT=1 claude-sandbox

# Kombinace
CLAUDE_GIT=0 CLAUDE_NETWORK=none CLAUDE_MEMORY=4g claude-sandbox
```

### Mountování vlastních adresářů

Ve výchozím stavu se do kontejneru mountuje pouze aktuální projektový adresář. Pomocí `CLAUDE_MOUNTS` můžeš zpřístupnit další adresáře z hostu — např. sdílená data, referenční repozitáře nebo datasety.

```bash
# Připojit jeden adresář (read-only)
CLAUDE_MOUNTS="/data/shared:/data/shared:ro" claude-sandbox

# Připojit více adresářů (oddělené čárkou)
CLAUDE_MOUNTS="/data/datasety:/data/datasety:ro,/mnt/reference:/mnt/reference:ro" claude-sandbox

# Read-write mount (pozor — Claude může soubory měnit)
CLAUDE_MOUNTS="/data/output:/data/output" claude-sandbox
```

Každý záznam odpovídá standardní Docker bind-mount syntaxi: `cesta_na_hostu:cesta_v_kontejneru[:volby]`. Pokud je to možné, používej `:ro` pro read-only přístup, aby nedošlo k nechtěným úpravám.

### Výchozí hodnoty

Výchozí hodnoty je možné změnit přímo ve scriptu `claude-sandbox.sh` v sekci:

```bash
NETWORK="${CLAUDE_NETWORK:-host}"
MEMORY="${CLAUDE_MEMORY:-8g}"
CPUS="${CLAUDE_CPUS:-4}"
GIT_ENABLED="${CLAUDE_GIT:-1}"
```

Hodnota za `:-` je výchozí, kterou lze přepsat env proměnnou.

## Git safety net (Worktree)

Pokud je zapnutý (`CLAUDE_GIT=1`, default), sandbox používá **git worktrees** k izolaci práce Claude od tvého projektu:

**Před spuštěním:**
- Inicializuje git repo pokud neexistuje
- Vytvoří worktree v `.claude-worktree` na nové branch `claude-sandbox/<timestamp>`
- Pokud worktree už existuje, nabídne pokračovat nebo vytvořit nový
- Tvůj originální projekt zůstane nedotčený — Claude pracuje ve worktree

**Po skončení:**
- Zobrazí přehled změn které Claude provedl
- Nabídne interaktivní menu:
  1. **Zobrazit diff** — side-by-side diff (pomocí `delta` pokud je k dispozici)
  2. **Kopírovat změny** — `rsync` souborů z worktree do projektu (bez `.git`)
  3. **Mergovat branch** — `git merge claude-sandbox/<ts>` do hlavní branch
  4. **Nechat worktree** — ponechat k pozdějšímu pokračování přes `claude-sandbox -r`
  5. **Smazat worktree** — zahodit změny a smazat branch

**Ruční cleanup kdykoliv:**

```bash
# Smazat worktree a branch
git worktree remove .claude-worktree
git branch -D claude-sandbox/<timestamp>
```

## Web development

Díky `--network host` (default) Claude může spouštět dev servery a ty je uvidíš na hostu:

```bash
claude-sandbox -p "vytvoř React aplikaci a spusť dev server"
# → otevři http://localhost:3000 v prohlížeči
```

## SSH a GitHub

Pro git push/pull přes SSH spusť na hostu SSH agenta:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Sandbox automaticky předá SSH agenta do kontejneru.

## Co je v kontejneru

- **Node.js 20** + npm, pnpm, yarn
- **Go 1.23.6** + gopls, delve, goimports, golangci-lint
- **TypeScript**, ts-node, ESLint, Prettier, nodemon
- **Python 3** + pip
- Git, curl, wget, jq, build-essential
- **Předpřipravené slash commands** — `/feature` (řízený vývoj funkce) a `/handoff` (poznámky k předání práce)
- **Předkonfigurované pluginy** — feature-dev, code-review, context7, superpowers, code-simplifier, claude-md-management

## Persistentní data

Mezi spuštěními se uchovávají:

| Data | Umístění na hostu |
|---|---|
| Claude sessions a auth | `~/.claude/`, `~/.claude.json` |
| Nastavení | `~/.config/`, `~/.local/` |
| Go moduly a nástroje | `~/.claude-sandbox/go/` |
| npm cache | `~/.claude-sandbox/npm/` |
| pip cache | `~/.claude-sandbox/pip/` |

### Reset cache

```bash
rm -rf ~/.claude-sandbox
```

## Řešení problémů

**Permission denied na Docker socket:**

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Claude nevidí SSH klíče:**

Ujisti se, že běží SSH agent: `echo $SSH_AUTH_SOCK`

**Chyba `.claude.json` not found:**

Script automaticky obnoví z backupu nebo vytvoří prázdný. Pokud přetrvává, přihlaš se znovu na hostu: `claude`

**Soubory v projektu mají špatná práva:**

Kontejner běží pod tvým UID/GID, takže by práva měla sedět. Pokud ne, zkontroluj: `ls -la` v projektu.

## Struktura souborů

```
claude-sandbox/
├── Dockerfile           # Docker image s nástroji
├── claude-sandbox.sh    # Spouštěcí script
├── commands/            # Předpřipravené slash commands
│   ├── feature.md       # /feature — řízený vývoj funkce
│   └── handoff.md       # /handoff — poznámky k předání práce
├── default-settings.json # Výchozí nastavení s pluginy
├── .gitignore           # Vylučuje .claude-worktree
└── README.md
```
