#!/bin/bash

# Scheduled backup script - runs daily
# Backs up all configuration files to backup directory

# Get script directory and project root for proper path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_ROOT/backup"
LOG_FILE="$PROJECT_ROOT/logs/scheduled-backup.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
KEEP_DAYS=${KEEP_DAYS:-3}  # Keep backups for 3 days by default (can override via env variable)

# Create directories if they don't exist
mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Load configuration if available
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Backup Home Assistant configuration
backup_homeassistant() {
    local ha_config="$PROJECT_ROOT/volumes/homeassistant/config"
    local backup_path="$BACKUP_DIR/homeassistant_$TIMESTAMP"
    
    if [ -d "$ha_config" ]; then
        log "Backing up Home Assistant configuration..."
        mkdir -p "$backup_path"
        
        # Copy main config files
        cp -r "$ha_config"/*.yaml "$backup_path/" 2>/dev/null
        cp -r "$ha_config/blueprints" "$backup_path/" 2>/dev/null
        cp -r "$ha_config/custom_components" "$backup_path/" 2>/dev/null
        
        log "Home Assistant config backed up to: $backup_path"
    else
        log "WARNING: Home Assistant config directory not found"
    fi
}

# Backup Nextcloud configuration
backup_nextcloud() {
    local nc_config="$PROJECT_ROOT/volumes/nextcloud/html/config"
    local backup_path="$BACKUP_DIR/nextcloud_$TIMESTAMP"
    
    if [ -d "$nc_config" ]; then
        log "Backing up Nextcloud configuration..."
        mkdir -p "$backup_path"
        
        # Copy config files
        cp -r "$nc_config"/*.php "$backup_path/" 2>/dev/null
        
        log "Nextcloud config backed up to: $backup_path"
    else
        log "WARNING: Nextcloud config directory not found"
    fi
}

# Backup Nginx configuration
backup_nginx() {
    local nginx_conf="$PROJECT_ROOT/nginx"
    local backup_path="$BACKUP_DIR/nginx_$TIMESTAMP"
    
    if [ -d "$nginx_conf" ]; then
        log "Backing up Nginx configuration..."
        mkdir -p "$backup_path"
        
        # Copy nginx configs
        cp -r "$nginx_conf/conf.d" "$backup_path/" 2>/dev/null
        
        log "Nginx config backed up to: $backup_path"
    else
        log "WARNING: Nginx config directory not found"
    fi
}

# Backup Docker Compose and environment files
backup_docker() {
    local backup_path="$BACKUP_DIR/docker_$TIMESTAMP"
    
    log "Backing up Docker configuration..."
    mkdir -p "$backup_path"
    
    # Copy docker-compose and .env
    [ -f "$SCRIPT_DIR/docker-compose.yml" ] && cp "$SCRIPT_DIR/docker-compose.yml" "$backup_path/"
    [ -f "$SCRIPT_DIR/.env" ] && cp "$SCRIPT_DIR/.env" "$backup_path/"
    
    # Copy all scripts
    cp "$SCRIPT_DIR"/*.sh "$backup_path/" 2>/dev/null
    
    log "Docker config backed up to: $backup_path"
}

# Backup network settings
backup_network() {
    local backup_path="$BACKUP_DIR/network_$TIMESTAMP"
    
    log "Backing up network configuration..."
    mkdir -p "$backup_path"
    
    # Network configuration files
    [ -f /etc/network/interfaces ] && sudo cp /etc/network/interfaces "$backup_path/" 2>/dev/null
    [ -d /etc/netplan ] && sudo cp -r /etc/netplan "$backup_path/" 2>/dev/null
    [ -f /etc/dhcpcd.conf ] && sudo cp /etc/dhcpcd.conf "$backup_path/" 2>/dev/null
    
    # Save current network state
    ip addr > "$backup_path/ip_addr.txt" 2>/dev/null
    ip route > "$backup_path/ip_route.txt" 2>/dev/null
    
    log "Network config backed up to: $backup_path"
}

# Cleanup old backups (keep last N days)
cleanup_old_backups() {
    log "Cleaning up old backups (keeping last $KEEP_DAYS days)..."
    
    # Find and remove directories older than KEEP_DAYS
    # Using maxdepth 1 to only check direct subdirectories in backup folder
    local removed_count=0
    
    while IFS= read -r -d '' backup_folder; do
        if [ -d "$backup_folder" ]; then
            rm -rf "$backup_folder"
            log "Removed old backup: $(basename "$backup_folder")"
            ((removed_count++))
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -not -path "$BACKUP_DIR" -print0 2>/dev/null)
    
    if [ $removed_count -eq 0 ]; then
        log "No old backups to remove"
    else
        log "Cleanup completed: removed $removed_count old backup(s)"
    fi
}

log "Starting scheduled backup job"

backup_homeassistant
backup_nextcloud
backup_nginx
backup_docker
backup_network
cleanup_old_backups

log "Scheduled backup job completed"
log "Backups saved in: $BACKUP_DIR"
