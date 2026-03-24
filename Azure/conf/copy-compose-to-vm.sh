#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR=""
COMPOSE_B64=""
ENV_B64=""

for arg in "$@"; do
  case "$arg" in
    remote_dir=*)
      REMOTE_DIR="${arg#*=}"
      ;;
    compose_b64=*)
      COMPOSE_B64="${arg#*=}"
      ;;
    env_b64=*)
      ENV_B64="${arg#*=}"
      ;;
    *)
      ;;
  esac
done

if [ -z "$REMOTE_DIR" ] || [ -z "$COMPOSE_B64" ] || [ -z "$ENV_B64" ]; then
  echo "Usage: $0 remote_dir=<path> compose_b64=<base64> env_b64=<base64>" >&2
  exit 1
fi

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
