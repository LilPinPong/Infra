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

install_blobfuse2() {
  local os_id
  local os_version
  local pkg_url
  local pkg_file

  if command -v blobfuse2 >/dev/null 2>&1; then
    log "INFO" "☁️ blobfuse2 is already installed"
    return 0
  fi

  if sudo apt-get install -y fuse3 blobfuse2 >>"$LOG_FILE" 2>&1; then
    log "INFO" "☁️ blobfuse2 installed from existing apt repositories"
    return 0
  fi

  run_step "📦 Install apt prerequisites for blobfuse2" sudo apt-get install -y ca-certificates curl wget gnupg lsb-release

  os_id="$(. /etc/os-release && echo "${ID}")"
  os_version="$(. /etc/os-release && echo "${VERSION_ID}")"
  pkg_url="https://packages.microsoft.com/config/${os_id}/${os_version}/packages-microsoft-prod.deb"
  pkg_file="/tmp/packages-microsoft-prod.deb"

  run_step "⬇️ Download Microsoft Linux repo package" wget -qO "$pkg_file" "$pkg_url"
  run_step "📦 Register Microsoft Linux repo" sudo dpkg -i "$pkg_file"
  rm -f "$pkg_file"

  run_step "🔄 Refresh apt index" sudo apt-get update -y
  run_step "☁️ Install blobfuse2 package" sudo apt-get install -y fuse3 blobfuse2
}

mount_azure_files_share() {
  local storage_account
  local storage_key
  local container_name
  local mount_point
  local tmp_path

  storage_account="${AZURE_STORAGE_ACCOUNT:-${STORAGE_ACCOUNT_NAME:-${R_STORAGE_ACCOUNT_NAME:-}}}"
  storage_key="${AZURE_STORAGE_ACCESS_KEY:-${AZURE_STORAGE_KEY:-${STORAGE_ACCOUNT_PASSWORD:-${R_STORAGE_ACCOUNT_PASSWORD:-}}}}"
  container_name="${AZURE_BLOB_CONTAINER:-${AZURE_STORAGE_ACCOUNT_CONTAINER:-${AZURE_FILE_SHARE:-${FILE_SHARE_NAME:-${R_FILE_SHARE_NAME:-share-azureinfra-dev-01}}}}}"
  mount_point="${AZURE_MOUNT_POINT:-/media/${container_name}}"
  tmp_path="${AZURE_BLOBFUSE_TMP_PATH:-/mnt/blobfuse2tmp/${container_name}}"

  if [ -z "$storage_account" ] || [ -z "$storage_key" ] || [ -z "$container_name" ]; then
    log "ERROR" "🛑 Missing blob settings. Provide account, key and container (AZURE_* or R_* variables)."
    return 1
  fi

  install_blobfuse2

  run_step "📁 Create blob mount directory" sudo mkdir -p "$mount_point"
  run_step "📁 Create blobfuse cache directory" sudo mkdir -p "$tmp_path"
  run_step "🔐 Set blobfuse cache ownership" sudo chown azureuser:azureuser "$tmp_path"
  run_step "🔐 Set blobfuse cache permissions" sudo chmod 700 "$tmp_path"

  if mountpoint -q "$mount_point"; then
    log "INFO" "☁️ Blob container already mounted at $mount_point"
  else
    run_step "☁️ Mount Blob container with blobfuse2" \
      sudo env \
      AZURE_STORAGE_ACCOUNT="$storage_account" \
      AZURE_STORAGE_AUTH_TYPE="Key" \
      AZURE_STORAGE_ACCESS_KEY="$storage_key" \
      AZURE_STORAGE_ACCOUNT_CONTAINER="$container_name" \
      blobfuse2 mount "$mount_point" --tmp-path="$tmp_path"
  fi
}

sync_caddyfile_from_storage_or_create() {
  local caddy_file="$1"
  local mount_point
  local container_name
  local storage_caddy_file
  local storage_caddy_dir
  local temp_caddy_file

  container_name="${AZURE_BLOB_CONTAINER:-${AZURE_STORAGE_ACCOUNT_CONTAINER:-${AZURE_FILE_SHARE:-${FILE_SHARE_NAME:-${R_FILE_SHARE_NAME:-share-azureinfra-dev-01}}}}}"
  mount_point="${AZURE_MOUNT_POINT:-/media/${container_name}}"
  storage_caddy_file="${AZURE_CADDYFILE_PATH:-${mount_point}/caddy/Caddyfile}"
  storage_caddy_dir="$(dirname "$storage_caddy_file")"
  temp_caddy_file="$(mktemp)"

  cat >"$temp_caddy_file" <<EOF
${DOMAIN} {
    reverse_proxy n8n:5678
}
EOF

  if [ -f "$storage_caddy_file" ]; then
    log "INFO" "☁️ Caddyfile found in Storage Account, copying to VM"
    run_step "📥 Copy Caddyfile from storage" sudo cp "$storage_caddy_file" "$caddy_file"
  else
    log "INFO" "☁️ Caddyfile not found in Storage Account, creating a new one"
    run_step "🧱 Build local Caddyfile" sudo cp "$temp_caddy_file" "$caddy_file"
    run_step "📁 Ensure storage caddy directory" sudo mkdir -p "$storage_caddy_dir"
    run_step "📤 Copy Caddyfile to storage" sudo cp "$caddy_file" "$storage_caddy_file"
  fi

  run_step "🔐 Ensure Caddyfile ownership" sudo chown azureuser:azureuser "$caddy_file"
  run_step "🔐 Ensure Caddyfile permissions" sudo chmod 644 "$caddy_file"
  rm -f "$temp_caddy_file"
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

  sync_caddyfile_from_storage_or_create "$caddy_file"
  log "INFO" "🔍 Caddyfile ready for ${DOMAIN}"
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
  mount_azure_files_share
  start_n8n_stack
  log "INFO" "🎉 Deployment update completed"
}

main "$@"
