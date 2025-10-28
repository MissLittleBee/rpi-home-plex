#!/bin/bash

# Scheduled Docker cleanup script - runs every 6 hours
# This keeps Docker environment clean by removing unused resources

# Get script directory and project root for proper path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/logs/scheduled-cleanup.log"
mkdir -p "$(dirname "$LOG_FILE")"

MAX_LOG_SIZE=10485760  # 10MB

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to rotate log if it gets too large
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log "Log rotated due to size limit"
    fi
}

# Main cleanup function
run_cleanup() {
    log "Starting scheduled Docker cleanup..."

    # Safety check: Don't cleanup if Docker Compose services are still starting
    cd "$(dirname "$(dirname "$0")")/tools"
    if docker compose ps -q >/dev/null 2>&1; then
        STARTING_SERVICES=$(docker compose ps --format json | jq -r '.State' | grep -v "running" | wc -l)
    else
        STARTING_SERVICES=0
    fi
    cd - >/dev/null
    
    if [ "$STARTING_SERVICES" -gt 0 ]; then
        log "Detected rpi_home services still starting ($STARTING_SERVICES not ready) - skipping cleanup for safety"
        return
    fi
    log "rpi_home services are stable - proceeding with cleanup"

    # Count containers before cleanup
    EXITED_COUNT=$(docker ps -a -f status=exited -q | wc -l)
    TOTAL_COUNT=$(docker ps -a -q | wc -l)

    log "Found $EXITED_COUNT exited containers out of $TOTAL_COUNT total containers"

    if [ $EXITED_COUNT -gt 0 ]; then
        # Remove exited containers
        log "Removing exited containers..."
        REMOVED_CONTAINERS=$(docker ps -a -f status=exited -q | xargs -r docker rm 2>/dev/null | wc -l)
        log "Removed $REMOVED_CONTAINERS exited containers"
    else
        log "No exited containers to remove"
    fi

    # Remove unused images (dangling images)
    log "Removing unused/dangling images..."
    REMOVED_IMAGES=$(docker image prune -f 2>/dev/null | grep "Total reclaimed space" || echo "No images removed")
    log "Image cleanup result: $REMOVED_IMAGES"

    # Remove unused networks (but preserve swarm networks)
    log "Removing unused networks..."
    REMOVED_NETWORKS=$(docker network prune -f 2>/dev/null | grep "Total reclaimed space" || echo "No networks removed")
    log "Network cleanup result: $REMOVED_NETWORKS"

    # Remove unused volumes (be careful with this - only dangling volumes)
    log "Removing unused volumes..."
    REMOVED_VOLUMES=$(docker volume prune -f 2>/dev/null | grep "Total reclaimed space" || echo "No volumes removed")
    log "Volume cleanup result: $REMOVED_VOLUMES"

    # Final container count
    FINAL_COUNT=$(docker ps -a -q | wc -l)
    log "Cleanup completed. Container count: $TOTAL_COUNT -> $FINAL_COUNT"

    # Fix storage permissions for all directories
    log "Checking storage permissions..."
    
    # Detect storage configuration dynamically
    CURRENT_USER="${USER:-$(whoami)}"
    MEDIA_GROUP_NAME="${MEDIA_GROUP_NAME:-media}"
    
    # Check if media group exists
    if ! getent group "$MEDIA_GROUP_NAME" >/dev/null 2>&1; then
        log "Media group '$MEDIA_GROUP_NAME' not found - skipping permission fix"
        return
    fi
    
    # Function to fix permissions for a storage directory
    fix_storage_permissions() {
        local DIR_PATH="$1"
        local DIR_TYPE="$2"
        
        if [ -d "$DIR_PATH" ]; then
            # Fix any files that don't have group write permissions
            FIXED_FILES=$(find "$DIR_PATH" -type f ! -perm -g+w -exec chmod g+w {} \; -print 2>/dev/null | wc -l)
            if [ "$FIXED_FILES" -gt 0 ]; then
                log "Fixed group write permissions on $FIXED_FILES $DIR_TYPE files"
            fi
            
            # Ensure all files belong to media group
            FIXED_GROUP=$(find "$DIR_PATH" ! -group "$MEDIA_GROUP_NAME" -exec chgrp "$MEDIA_GROUP_NAME" {} \; -print 2>/dev/null | wc -l)
            if [ "$FIXED_GROUP" -gt 0 ]; then
                log "Fixed $MEDIA_GROUP_NAME group ownership on $FIXED_GROUP $DIR_TYPE files"
            fi
            
            return $(($FIXED_FILES + $FIXED_GROUP))
        else
            log "$DIR_TYPE directory $DIR_PATH not found - skipping"
            return 0
        fi
    }
    
    # Detect storage paths
    DETECTED_VIDEO_PATH="${VIDEO_PATH:-/home/$CURRENT_USER/videos}"
    DETECTED_IMAGE_PATH="${IMAGE_PATH:-/home/$CURRENT_USER/images}"
    DETECTED_DOC_PATH="${DOC_PATH:-/home/$CURRENT_USER/documents}"
    
    # Fix permissions for all storage directories
    TOTAL_FIXED=0
    fix_storage_permissions "$DETECTED_VIDEO_PATH" "video"
    TOTAL_FIXED=$(($TOTAL_FIXED + $?))
    
    fix_storage_permissions "$DETECTED_IMAGE_PATH" "image"
    TOTAL_FIXED=$(($TOTAL_FIXED + $?))
    
    fix_storage_permissions "$DETECTED_DOC_PATH" "document"
    TOTAL_FIXED=$(($TOTAL_FIXED + $?))
    
    if [ "$TOTAL_FIXED" -eq 0 ]; then
        log "Storage permissions are already correct"
    else
        log "Fixed permissions on $TOTAL_FIXED total files across all storage directories"
    fi

    # Rotate log if needed
    rotate_log

    log "Scheduled Docker cleanup finished"
    echo "---" >> "$LOG_FILE"
}

# Function to show usage
show_usage() {
    echo "Scheduled Docker Cleanup Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  cleanup     Run docker cleanup now (default)"
    echo "  help        Show this help message"
    echo ""
    echo "This script is designed to be run by cron every 6 hours."
    echo "Logs are written to: $LOG_FILE"
}

# Main script logic
case "${1:-cleanup}" in
    "cleanup")
        run_cleanup
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac