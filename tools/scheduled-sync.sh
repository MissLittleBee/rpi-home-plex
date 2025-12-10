#!/bin/bash

# Scheduled sync script - runs every 10 minutes
# This ensures both Plex and Nextcloud stay in sync

# Get script directory and project root for proper path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/logs/scheduled-sync.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Load configuration if available
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Wait for Docker containers to be ready after reboot
wait_for_containers() {
    local max_wait=300  # 5 minutes max wait
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker ps | grep -q "nextcloud" && docker ps | grep -q "plex"; then
            log "Containers are ready"
            return 0
        fi
        log "Waiting for containers to start... (${wait_time}s)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    log "ERROR: Timeout waiting for containers"
    return 1
}

get_nextcloud_container() {
    docker ps --format "table {{.ID}}\t{{.Image}}" | grep "nextcloud" | awk '{print $1}' | head -1
}

# Quick Nextcloud scan (only new/changed files)
quick_nextcloud_scan() {
    local container_id=$(get_nextcloud_container)
    if [ -n "$container_id" ]; then
        log "Running quick Nextcloud sync..."
        docker exec -u www-data "$container_id" php /var/www/html/occ files:scan --shallow --all 2>/dev/null
        log "Nextcloud quick sync completed"
    else
        log "ERROR: Nextcloud container not found"
    fi
}

# Plex library refresh (non-disruptive)
plex_library_refresh() {
    if [ -z "$PLEX_TOKEN" ]; then
        log "ERROR: PLEX_TOKEN not configured in .env"
        return 1
    fi
    
    local plex_url="http://localhost:32400"
    
    log "Refreshing Plex library..."
    
    # Get all library sections
    local sections=$(curl -s "${plex_url}/library/sections?X-Plex-Token=${PLEX_TOKEN}" | grep -o 'key="[0-9]*"' | grep -o '[0-9]*')
    
    if [ -z "$sections" ]; then
        log "ERROR: Could not retrieve Plex library sections"
        return 1
    fi
    
    # Refresh each section (Movies and TV Shows)
    for section_id in $sections; do
        local section_name=$(curl -s "${plex_url}/library/sections/${section_id}?X-Plex-Token=${PLEX_TOKEN}" | grep -o 'title="[^"]*"' | head -1 | cut -d'"' -f2)
        log "Scanning Plex library section: ${section_name} (ID: ${section_id})"
        curl -s "${plex_url}/library/sections/${section_id}/refresh?X-Plex-Token=${PLEX_TOKEN}" -X GET >/dev/null
    done
    
    log "Plex library refresh completed for all sections"
}

# Function to update Plex preferences for reverse proxy configuration (run once)
update_plex_config_for_reverse_proxy() {
    local plex_config_path="$PROJECT_ROOT/volumes/plex/config/Library/Application Support/Plex Media Server/Preferences.xml"
    
    if [ -f "$plex_config_path" ] && [ -n "$HOSTNAME" ] && [ -n "$SERVER_IP" ]; then
        # Check if reverse proxy config is already applied
        if ! grep -q "customConnections" "$plex_config_path"; then
            log "Configuring Plex for reverse proxy access..."
            
            # Create backup
            cp "$plex_config_path" "${plex_config_path}.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Update Plex preferences with reverse proxy settings
            sed -i "s/LastAutomaticMappedPort=\"[^\"]*\"/LastAutomaticMappedPort=\"0\" customConnections=\"https:\/\/${HOSTNAME}:443\/plex,http:\/\/${SERVER_IP}:32400\" allowedNetworks=\"10.0.0.0\/8,172.16.0.0\/12,192.168.0.0\/16,127.0.0.1\/32\" TreatWanIpAsLocal=\"1\" DisableRemoteSecurity=\"1\" LocalNetworkAddresses=\"${SERVER_IP}\" LanNetworksBandwidth=\"10.10.10.0\/24,172.16.0.0\/12,192.168.0.0\/16\"/" "$plex_config_path"
            
            log "Plex reverse proxy configuration applied - restart required"
            return 1  # Signal that restart is needed
        fi
    fi
    return 0  # No restart needed
}

log "Starting scheduled sync job"

# Wait for containers to be ready (important after reboot)
if ! wait_for_containers; then
    log "Sync aborted - containers not ready"
    exit 1
fi

# Check and apply Plex reverse proxy configuration if needed
if ! update_plex_config_for_reverse_proxy; then
    log "Restarting Plex container to apply reverse proxy configuration..."
    docker restart rpi_home_plex >/dev/null 2>&1
    sleep 15  # Give Plex time to restart
fi

quick_nextcloud_scan
sleep 2
plex_library_refresh
log "Scheduled sync job completed"