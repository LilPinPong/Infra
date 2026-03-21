#!/bin/bash

LOG_FILE="<Path of the logs files>"
# Ensure log file exists
touch "$LOG_FILE"

    log() {
        local level="$1"
        local message="$2"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
    }

log "INFO" "🔄 Machines is currently updating..." | tee -a "$LOG_FILE"

declare -A machine_commands
machine_commands=(
    
     ["Update Machine"]="sudo apt install \
                         sudo apt update \
                         sudo apt upgrade -y"

     ["Docker installer"]="sudo apt update \
                           sudo apt install ca-certificates curl \
                           sudo install -m 0755 -d /etc/apt/keyrings \
                           sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
                           sudo chmod a+r /etc/apt/keyrings/docker.asc \

                           # Add the repository to Apt sources: 
                           sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
                            Types: deb
                            URIs: https://download.docker.com/linux/debian
                            Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
                            Components: stable
                            Signed-By: /etc/apt/keyrings/docker.asc
                           EOF"
    ["mount stvm"]=""

    ["compose n8n"]="docker compose up -d"

)

update_machine() {
    local image_name="$1"
    local start_command="$2"

    log "INFO" "🔍 Searching for:🐳 $image_name"

    # Extract container name from the start command
    local container_name=$(echo "$start_command" | awk '{for(i=1;i<=NF;i++) if ($i == "--name") print $(i+1)}')
    
    if [ -z "$container_name" ]; then
        log "ERROR" "❌ No container name found in the start command."
        return 1
    fi

    local container_id=$(docker ps -a --filter "name=$container_name" --format "{{.ID}}")

    if [ -n "$container_id" ]; then
        log "INFO" "🛑 Stopping current container: $container_name"
        if docker stop "$container_name" &>> "$LOG_FILE"; then
            log "INFO" "✅ Successfully stopped $container_name"
        else
            log "ERROR" "❌ Failed to stop $container_name"
        fi

        log "INFO" "🗑  Removing container: $container_name"
        if docker rm "$container_name" &>> "$LOG_FILE"; then
            log "INFO" "✅ Successfully removed $container_name"
        else
            log "ERROR" "❌ Failed to remove $container_name"
        fi
    else
        log "WARN" "⚠️ No running container found for: $container_name"
    fi

    log "INFO" "🚀 Starting updated container: $container_name"
    if eval "$start_command" &>> "$LOG_FILE"; then
        log "INFO" "✅ Successfully started container: $container_name"
    else
        log "ERROR" "❌ Failed to start container: $container_name"
    fi
}


declare -a startup_order=(
    "All the image in the order you need to be restarted"
)

for image in "${startup_order[@]}"; do
    update_machine "$image" "${images[$image]}"
done

log "INFO" "✅ Update done. 🎉🎉🎉!" | tee -a "$LOG_FILE"