#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${LOG_FILE:-/var/log/n8n-bootstrap.log}"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log() {
  local level="$1"
  local message="$2"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
}

run_step() {
  local step_name="$1"
  shift
  log "INFO" "Starting: $step_name"
  if "$@" >>"$LOG_FILE" 2>&1; then
    log "INFO" "Completed: $step_name"
  else
    log "ERROR" "Failed: $step_name"
    return 1
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "INFO" "Docker is already installed"
    return 0
  fi

  run_step "Install apt prerequisites" sudo apt-get install -y ca-certificates curl
  run_step "Create keyring directory" sudo install -m 0755 -d /etc/apt/keyrings
  run_step "Download Docker GPG key" sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  run_step "Set GPG key permissions" sudo chmod a+r /etc/apt/keyrings/docker.asc

  local codename
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  run_step "Refresh apt index for Docker repo" sudo apt-get update -y
  run_step "Install Docker engine and compose plugin" sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

find_compose_dir() {
  local candidates=(
    "${COMPOSE_DIR:-}"
    "$PWD"
    "$PWD/conf"
    "/home/azureuser/conf"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    [ -z "$candidate" ] && continue
    if [ -f "$candidate/docker-compose.yml" ] || [ -f "$candidate/compose.yml" ] || [ -f "$candidate/compose.yaml" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

start_n8n_stack() {
  local compose_dir
  compose_dir="$(find_compose_dir)" || {
    log "ERROR" "🛑 No compose file found. Set COMPOSE_DIR or place compose file in /home/azureuser/conf."
    return 1
  }

  run_step "🔍 Start n8n stack from $compose_dir 🐳" bash -lc "cd '$compose_dir' && sudo docker compose up -d"
}

main() {
  if [ -n "${1:-}" ]; then
    COMPOSE_DIR="$1"
  fi

  log "✅ INFO" "Machine update and n8n deployment started"
  run_step "🔍 Update apt index" sudo apt-get update -y
  run_step "✅ Upgrade installed packages" sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  install_docker
  run_step "🐳 Enable and start Docker service" sudo systemctl enable --now docker
  start_n8n_stack
  log "✅ INFO" "Deployment update completed"
}

main "$@"
