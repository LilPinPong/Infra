#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <remote_dir> <compose_b64> <env_b64>" >&2
  exit 1
fi

REMOTE_DIR="$1"
COMPOSE_B64="$2"
ENV_B64="$3"

sudo mkdir -p "$REMOTE_DIR"
printf '%s' "$COMPOSE_B64" | base64 -d | sudo tee "$REMOTE_DIR/compose.yml" >/dev/null
printf '%s' "$ENV_B64" | base64 -d | sudo tee "$REMOTE_DIR/.env" >/dev/null

sudo chown -R azureuser:azureuser "$REMOTE_DIR"
sudo chmod 644 "$REMOTE_DIR/compose.yml"
sudo chmod 640 "$REMOTE_DIR/.env"

if [ ! -s "$REMOTE_DIR/compose.yml" ]; then
  echo "ERROR: compose.yml is empty after copy" >&2
  exit 1
fi

if [ ! -s "$REMOTE_DIR/.env" ]; then
  echo "ERROR: .env is empty after copy" >&2
  exit 1
fi

ls -la "$REMOTE_DIR"
wc -c "$REMOTE_DIR/compose.yml" "$REMOTE_DIR/.env"
