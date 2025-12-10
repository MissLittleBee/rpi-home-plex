#!/bin/bash
# generate_cloudflare_config.sh - Generate Cloudflare configuration from environment variables

# Get project root directory  
PROJECT_ROOT="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/.env"

echo "Generating cloudflare tunnel configuration..."

# Create backup if file already exists
if [ -f "$PROJECT_ROOT/volumes/cloudflare/config/config.yml" ]; then
    BACKUP_FILE="$PROJECT_ROOT/volumes/cloudflare/config/config.yml.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$PROJECT_ROOT/volumes/cloudflare/config/config.yml" "$BACKUP_FILE"
    echo "✓ Backed up existing cloudflare config to: $(basename "$BACKUP_FILE")"
fi

cat > "$PROJECT_ROOT/volumes/cloudflare/config/config.yml" << EOF
# Minimal configuration of Cloudflare Tunnel for services
tunnel: ${CLOUDFLARE_TUNNEL_NAME}

ingress:
  # Route traffic to nginx reverse proxy for all services
  - hostname: ha.${DOMAIN_NAME}
    service: http://${SERVER_IP}:8123
  
  - hostname: plex.${DOMAIN_NAME}
    service: http://${SERVER_IP}:32400
  
  - hostname: nextcloud.${DOMAIN_NAME}
    service: http://${SERVER_IP}:80

  # Catch-all rule (required)
  - service: http_status:404
EOF
echo "✓ Generated cloudflare config at: volumes/cloudflare/config/config.yml"