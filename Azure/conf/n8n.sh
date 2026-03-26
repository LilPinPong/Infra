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
  log "INFO" "🔍 Starting: $step_name"
  if "$@" >>"$LOG_FILE" 2>&1; then
    log "INFO" "✅ Completed: $step_name"
  else
    log "ERROR" "🛑 Failed: $step_name"
    return 1
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "INFO" "🐳 Docker is already installed"
    return 0
  fi

  run_step "📦 Install apt prerequisites" sudo apt-get install -y ca-certificates curl
  run_step "📁 Create keyring directory" sudo install -m 0755 -d /etc/apt/keyrings
  run_step "🔐 Download Docker GPG key" sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  run_step "🔒 Set GPG key permissions" sudo chmod a+r /etc/apt/keyrings/docker.asc

  local codename
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  run_step "🔄 Refresh apt index for Docker repo" sudo apt-get update -y
  run_step "🐳 Install Docker engine and compose plugin" sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ensure_azureuser_docker_group() {
  if ! id -u azureuser >/dev/null 2>&1; then
    log "ERROR" "🛑 User azureuser does not exist on this VM."
    return 1
  fi

  if ! getent group docker >/dev/null 2>&1; then
    run_step "👥 Create docker group" sudo groupadd docker
  fi

  if id -nG azureuser | tr ' ' '\n' | grep -qx docker; then
    log "INFO" "👥 azureuser is already in docker group"
  else
    run_step "👥 Add azureuser to docker group" sudo usermod -aG docker azureuser
    log "INFO" "✅ azureuser added to docker group"
  fi
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
  local compose_file
  local compose_output
  local caddy_dir
  local caddy_file

  compose_dir="$(find_compose_dir)" || {
    log "ERROR" "🛑 No compose file found. Set COMPOSE_DIR or place compose file in /home/azureuser/conf."
    return 1
  }

  if [ -f "$compose_dir/compose.yml" ]; then
    compose_file="$compose_dir/compose.yml"
  elif [ -f "$compose_dir/compose.yaml" ]; then
    compose_file="$compose_dir/compose.yaml"
  elif [ -f "$compose_dir/docker-compose.yml" ]; then
    compose_file="$compose_dir/docker-compose.yml"
  else
    log "ERROR" "🛑 Compose file not found in $compose_dir."
    return 1
  fi

  log "INFO" "🔍 Using compose file: $compose_file"
  compose_output="$(mktemp)"
  caddy_dir="$compose_dir/conf"
  caddy_file="$caddy_dir/Caddyfile"

  # Ensure azureuser can read compose inputs before running docker compose as azureuser.
  run_step "🔐 Ensure ownership of compose assets" sudo chown azureuser:azureuser "$compose_dir" "$compose_file" "$compose_dir/.env"
  run_step "🔐 Ensure compose file permissions" sudo chmod 755 "$compose_dir"
  run_step "🔐 Ensure compose.yml permissions" sudo chmod 644 "$compose_file"
  run_step "🔐 Ensure .env permissions" sudo chmod 640 "$compose_dir/.env"
  run_step "📁 Ensure caddy config directory" sudo mkdir -p "$caddy_dir"
  run_step "🔐 Ensure caddy config ownership" sudo chown -R azureuser:azureuser "$caddy_dir"
  run_step "🔐 Ensure caddy config permissions" sudo chmod 755 "$caddy_dir"

  set -a
  # shellcheck source=/dev/null
  . "$compose_dir/.env"
  set +a

  if [ -z "${N8N_SUBDOMAIN:-}" ] || [ -z "${DOMAIN:-}" ]; then
    log "ERROR" "🛑 N8N_SUBDOMAIN or DOMAIN missing in $compose_dir/.env"
    return 1
  fi

  cat >"$compose_output" <<EOF
${DOMAIN} {
    reverse_proxy n8n:5678
}
EOF
  run_step "🧱 Build Caddyfile" sudo cp "$compose_output" "$caddy_file"
  run_step "🔐 Ensure Caddyfile ownership" sudo chown azureuser:azureuser "$caddy_file"
  run_step "🔐 Ensure Caddyfile permissions" sudo chmod 644 "$caddy_file"
  log "INFO" "🔍 Caddyfile generated for ${DOMAIN}"
  rm -f "$compose_output"
  compose_output="$(mktemp)"
  log "INFO" "🔍 Compose asset permissions:"
  ls -ld "$compose_dir" | tee -a "$LOG_FILE"
  ls -l "$compose_file" "$compose_dir/.env" | tee -a "$LOG_FILE"
  ls -l "$caddy_file" | tee -a "$LOG_FILE"
  id azureuser | tee -a "$LOG_FILE"

  if sudo -u azureuser bash -lc "cd '$compose_dir' && docker compose -f '$compose_file' --env-file '$compose_dir/.env' config" >"$compose_output" 2>&1; then
    log "INFO" "✅ Compose configuration is valid"
  else
    log "ERROR" "🛑 Compose validation failed"
    while IFS= read -r line; do
      log "ERROR" "🧾 $line"
    done <"$compose_output"
    rm -f "$compose_output"
    return 1
  fi

  if sudo -u azureuser bash -lc "cd '$compose_dir' && docker compose -f '$compose_file' --env-file '$compose_dir/.env' up -d" >"$compose_output" 2>&1; then
    log "INFO" "✅ n8n stack started successfully"
  else
    log "ERROR" "🛑 Failed to start n8n stack"
    while IFS= read -r line; do
      log "ERROR" "🧾 $line"
    done <"$compose_output"
    rm -f "$compose_output"
    return 1
  fi

  cat "$compose_output" >>"$LOG_FILE"
  rm -f "$compose_output"
}

main() {
  if [ -n "${1:-}" ]; then
    COMPOSE_DIR="$1"
  fi

  log "INFO" "✅ Machine update and n8n deployment started"
  run_step "🔍 Update apt index" sudo apt-get update -y
  run_step "⬆️ Upgrade installed packages" sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  install_docker
  run_step "🐳 Enable and start Docker service" sudo systemctl enable --now docker
  ensure_azureuser_docker_group
  start_n8n_stack
  log "INFO" "🎉 Deployment update completed"
}

main "$@"
