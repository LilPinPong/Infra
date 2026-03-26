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

mount_azure_files_share() {
  local storage_account
  local storage_key
  local file_share
  local mount_point
  local cred_dir
  local cred_file
  local share_path
  local fstab_entry
  local azure_uid
  local azure_gid
  local tmp_creds

  storage_account="${AZURE_STORAGE_ACCOUNT:-}"
  storage_key="${AZURE_STORAGE_KEY:-}"
  file_share="${AZURE_FILE_SHARE:-}"
  mount_point="${AZURE_MOUNT_POINT:-/mnt/azurefiles}"

  if [ -z "$storage_account" ] || [ -z "$storage_key" ] || [ -z "$file_share" ]; then
    log "ERROR" "🛑 AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_KEY or AZURE_FILE_SHARE is missing."
    return 1
  fi

  cred_dir="/etc/smbcredentials"
  cred_file="${cred_dir}/${storage_account}.cred"
  share_path="//${storage_account}.file.core.windows.net/${file_share}"
  azure_uid="$(id -u azureuser)"
  azure_gid="$(id -g azureuser)"

  run_step "📦 Install cifs-utils" sudo apt-get install -y cifs-utils
  run_step "📁 Create smb credentials directory" sudo mkdir -p "$cred_dir"

  tmp_creds="$(mktemp)"
  chmod 600 "$tmp_creds"
  cat >"$tmp_creds" <<EOF
username=${storage_account}
password=${storage_key}
EOF
  run_step "🔐 Install SMB credentials file" sudo install -m 600 "$tmp_creds" "$cred_file"
  rm -f "$tmp_creds"

  run_step "📁 Create Azure Files mount point" sudo mkdir -p "$mount_point"

  fstab_entry="${share_path} ${mount_point} cifs nofail,_netdev,credentials=${cred_file},uid=${azure_uid},gid=${azure_gid},dir_mode=0770,file_mode=0660,serverino,vers=3.0,actimeo=30,mfsymlinks,nosharesock,x-systemd.automount 0 0"
  if grep -qF "${share_path} ${mount_point} cifs" /etc/fstab; then
    log "INFO" "🧾 Azure Files fstab entry already present"
  else
    run_step "🧾 Add Azure Files mount to fstab" sudo bash -lc "printf '%s\n' \"$fstab_entry\" >> /etc/fstab"
  fi

  if mountpoint -q "$mount_point"; then
    log "INFO" "☁️ Azure Files share already mounted at $mount_point"
  else
    run_step "☁️ Mount Azure Files share" sudo mount "$mount_point"
  fi
}

sync_caddyfile_from_storage_or_create() {
  local caddy_file="$1"
  local mount_point
  local storage_caddy_file
  local storage_caddy_dir
  local temp_caddy_file

  mount_point="${AZURE_MOUNT_POINT:-/mnt/azurefiles}"
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
