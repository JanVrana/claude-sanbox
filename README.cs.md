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

```bash
# Bez sítě (úplný sandbox)
CLAUDE_NETWORK=none claude-sandbox

# Víc zdrojů pro náročný build
CLAUDE_MEMORY=16g CLAUDE_CPUS=5 claude-sandbox

# Bez git zálohy
CLAUDE_GIT=0 claude-sandbox

# Kombinace
CLAUDE_GIT=0 CLAUDE_NETWORK=none CLAUDE_MEMORY=4g claude-sandbox
```

### Výchozí hodnoty

Výchozí hodnoty je možné změnit přímo ve scriptu `claude-sandbox.sh` v sekci:

```bash
NETWORK="${CLAUDE_NETWORK:-host}"
MEMORY="${CLAUDE_MEMORY:-8g}"
CPUS="${CLAUDE_CPUS:-4}"
GIT_ENABLED="${CLAUDE_GIT:-1}"
```

Hodnota za `:-` je výchozí, kterou lze přepsat env proměnnou.

## Git safety net

Pokud je zapnutý (`CLAUDE_GIT=1`, default):

**Před spuštěním:**
- Inicializuje git repo pokud neexistuje
- Zastashuje neuložené změny
- Vytvoří záložní branch `claude-sandbox-backup/<timestamp>`

**Po skončení:**
- Zobrazí přehled změn které Claude provedl
- Nabídne interaktivní menu:
  1. **Přijmout** — commitne změny (s AI-generovanou commit message)
  2. **Zobrazit diff** — detailní náhled změn, pak přijmout/vrátit
  3. **Vrátit vše** — zahodí všechny změny
  4. **Nechat** — ponechá změny v working directory k ruční kontrole

**Ruční návrat kdykoliv:**

```bash
# Vrátit na zálohu
git reset --hard claude-sandbox-backup/<timestamp>

# Obnovit zastashované změny
git stash pop
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
└── README.md
```
