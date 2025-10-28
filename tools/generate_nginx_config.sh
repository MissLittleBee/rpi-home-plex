#!/bin/bash
# generate_nginx_config.sh - Generate nginx configuration from environment variables

# Get project root directory  
PROJECT_ROOT="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/.env"

echo "Generating nginx configuration..."

# Create backup if file already exists
if [ -f "$PROJECT_ROOT/nginx/conf.d/default.conf" ]; then
    BACKUP_FILE="$PROJECT_ROOT/nginx/conf.d/default.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$PROJECT_ROOT/nginx/conf.d/default.conf" "$BACKUP_FILE"
    echo "✓ Backed up existing nginx config to: $(basename "$BACKUP_FILE")"
fi

cat > "$PROJECT_ROOT/nginx/conf.d/default.conf" << EOF
# Recommended nginx configuration for Nextcloud and Home Assistant reverse proxy

# WebSocket connection upgrade map
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

# Mobile app detection
map \$http_user_agent \$mobile {
    default 0;
    "~*Nextcloud" 1;
    "~*ownCloud" 1;
    "~*mirall" 1;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name _;
    return 301 https://\$host\$request_uri;
}

# Main server block for all services
server {
    listen 443 ssl;
    server_name ${HOSTNAME} ${SERVER_IP} ${VPN_IP} _;

    ssl_certificate /etc/ssl/private/server.crt;
    ssl_certificate_key /etc/ssl/private/server.key;

    # Security headers
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "no-referrer";
    add_header Permissions-Policy "interest-cohort=()";

    # Nextcloud location - simplified for mobile app compatibility
    location /nextcloud {
        return 301 /nextcloud/;
    }
    
    location /nextcloud/ {
        # Add trailing slash to proxy_pass to strip /nextcloud/ from path
        proxy_pass http://app:80/;
        
        # Essential headers for Nextcloud
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
        
        # Mobile app specific headers
        proxy_set_header X-Forwarded-Prefix /nextcloud;
        proxy_set_header X-Script-Name /nextcloud;
        
        # Request handling
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 10G;
        proxy_read_timeout 3600;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_http_version 1.1;
    }

    # Jellyfin media server - proxy through nginx for VPN compatibility
    location /jellyfin {
        return 302 https://\$host/jellyfin/;
    }
    
    location /jellyfin/ {
        proxy_pass http://jellyfin:8096/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Prefix /jellyfin;
        proxy_buffering off;
        proxy_read_timeout 3600;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        
        # Headers for media streaming
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_http_version 1.1;
    }
    
    location /dlna {
        return 302 https://\$host/jellyfin/;
    }

    # Webshare Search service
    location /ws {
        return 302 https://\$host/ws/;
    }
    
    location /ws/ {
        proxy_pass http://webshare-search:5000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Prefix /ws;
        proxy_buffering off;
        proxy_read_timeout 3600;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }

    # Home Assistant - proxy entire root to HA
    location / {
        proxy_pass http://${SERVER_IP}:8123;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_buffering off;
        proxy_read_timeout 3600;
        
        # WebSocket support for Home Assistant
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_http_version 1.1;
    }
}
EOF

echo "✓ Nginx configuration generated for:"
echo "  Hostname: ${HOSTNAME}"
echo "  Server IP: ${SERVER_IP}"
echo "  VPN IP: ${VPN_IP}"