#!/bin/bash
set -euo pipefail

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
HOST_USER="${HOST_USER:-claude}"
HOST_HOME="${HOST_HOME:-/home/$HOST_USER}"

# Vytvoř skupinu pokud neexistuje
if ! getent group "$HOST_GID" >/dev/null 2>&1; then
  groupadd -g "$HOST_GID" "$HOST_USER"
fi

# Vytvoř uživatele nebo uprav existujícího (node UID 1000)
EXISTING=$(getent passwd "$HOST_UID" | cut -d: -f1 || true)
if [ -z "$EXISTING" ]; then
  useradd -u "$HOST_UID" -g "$HOST_GID" -d "$HOST_HOME" -s /bin/bash -M "$HOST_USER"
else
  usermod -d "$HOST_HOME" -l "$HOST_USER" "$EXISTING" 2>/dev/null || true
fi

export HOME="$HOST_HOME"

exec gosu "$HOST_UID" claude --dangerously-skip-permissions "$@"
