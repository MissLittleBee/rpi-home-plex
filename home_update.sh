#!/bin/bash
# home_update.sh: Update Docker images and redeploy stack with minimal downtime

set -e

STACK_NAME="rpi_home"

echo "=== Docker Images Update Script ==="
echo "This will update all images and redeploy the stack"
echo ""

# Function to check if stack exists
stack_exists() {
    docker compose -f tools/docker-compose.yml ps -q | grep -q .
}

# Show current image versions
echo "Current image versions:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" | grep -E "(nginx|mariadb|nextcloud|home-assistant|plex|webshare)" || echo "No relevant images found"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with the update? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
fi

echo ""
echo "=== Step 1: Pulling latest images ==="

# Pull latest versions of all images from docker-compose.yml
echo "Pulling nginx:latest..."
docker pull nginx:latest

echo "Pulling mariadb:10.11..."
docker pull mariadb:10.11

echo "Pulling nextcloud:stable..."
docker pull nextcloud:stable

echo "Pulling ghcr.io/home-assistant/home-assistant:stable..."
docker pull ghcr.io/home-assistant/home-assistant:stable

echo "Pulling linuxserver/plex:latest..."
docker pull linuxserver/plex:latest

echo "Building webshare-search service..."
docker build -f tools/Dockerfile.webshare -t rpi_home_webshare-search .

# Generate random passwords for secrets (no logging)

echo ""
echo "=== Step 2: Validating configuration and redeploying stack ==="

# Validate configuration before deployment
if [ -f "./tools/validate_config.sh" ] && [ -x "./tools/validate_config.sh" ]; then
    echo "Validating configuration..."
    if ./tools/validate_config.sh > /dev/null 2>&1; then
        echo "✓ Configuration is valid"
    else
        echo "❌ Configuration validation failed:"
        ./tools/validate_config.sh
        echo ""
        echo "Please fix configuration issues before updating."
        exit 1
    fi
else
    echo "⚠️  Configuration validation script not found - proceeding anyway"
fi

# Export environment variables for Docker Compose
if [ -f "tools/.env" ]; then
    export $(grep -v '^#' tools/.env | xargs)
fi

if stack_exists; then
    echo "Stack exists, performing rolling update..."
    # Docker Compose will recreate containers with new images
    cd tools
    docker compose up -d --force-recreate
    cd ..
    
    echo "Waiting for services to update..."
    sleep 5
    
    # Check service status
    echo ""
    echo "Service status after update:"
    docker compose -f tools/docker-compose.yml ps
    
else
    echo "Stack doesn't exist, deploying fresh..."
    cd tools
    docker compose up -d
    cd ..
fi

echo ""
echo "=== Step 3: Cleanup old images ==="

read -p "Do you want to remove unused/old Docker images to save space? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing unused Docker images..."
    docker image prune -f
    echo "Cleanup completed."
fi

echo ""
echo "=== Update Complete! ==="
echo "New image versions:"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" | grep -E "(nginx|mariadb|nextcloud|home-assistant|plex|webshare)" || echo "No relevant images found"

# Refresh storage permissions and trigger sync after update
echo "Refreshing storage permissions and libraries..."

# Ensure storage permissions are correct after container updates
if [ -f "./tools/scheduled-cleanup.sh" ] && [ -x "./tools/scheduled-cleanup.sh" ]; then
    echo "Checking storage permissions..."
    ./tools/scheduled-cleanup.sh cleanup | grep -A5 "storage permissions" || echo "✓ Storage permissions checked"
fi

# Trigger library sync to refresh libraries
if [ -f "./tools/scheduled-sync.sh" ] && [ -x "./tools/scheduled-sync.sh" ]; then
    ./tools/scheduled-sync.sh
    echo "✓ Library sync completed"
else
    echo "⚠️  Sync script not found - libraries may need manual refresh"
fi

echo ""
echo "=== 🎉 Update Complete! ==="
echo ""
# Load configuration for dynamic URLs
if [ -f "tools/.env" ]; then
    source tools/.env
    HOSTNAME=${HOSTNAME:-ha.local}
else
    HOSTNAME="ha.local"
fi

echo "📁 Access your services:"
echo "  • Home Assistant: https://${HOSTNAME}/"
echo "  • Nextcloud: https://${HOSTNAME}/nextcloud/"
echo "  • Plex Media Server: https://${HOSTNAME}/plex/"
echo "  • Webshare Search: https://${HOSTNAME}/ws/ (or http://${HOSTNAME}:5000/)"
echo ""
echo "🔄 Automation status:"
if crontab -l 2>/dev/null | grep -q "scheduled-sync.sh"; then
    echo "  ✓ Auto-sync is configured and running (every 10 minutes)"
else
    echo "  ⚠️  Auto-sync not configured - run ./home_start.sh to set up"
fi

if crontab -l 2>/dev/null | grep -q "scheduled-cleanup.sh"; then
    echo "  ✓ Auto-cleanup is configured and running (every 6 hours)"
else
    echo "  ⚠️  Auto-cleanup not configured - run ./home_start.sh to set up"
fi

echo ""
echo "📋 Useful commands:"
echo "  • Check sync logs: tail -f logs/scheduled-sync.log"
echo "  • Check cleanup logs: tail -f logs/scheduled-cleanup.log"
echo "  • Manual sync: ./tools/scheduled-sync.sh"
echo "  • Manual cleanup: ./tools/scheduled-cleanup.sh cleanup"
echo "  • Validate config: ./tools/validate_config.sh"