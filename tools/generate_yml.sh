#!/bin/bash
# generate_yml.sh: Generate docker-compose.yml dynamically based on configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load configuration
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "❌ .env file not found. Please run home_start.sh first to create configuration."
    exit 1
fi

echo "🔧 Generating docker-compose.yml..."

# Create docker-compose.yml
cat > "$SCRIPT_DIR/docker-compose.yml" << 'EOF'
services:
  nginx:
    image: nginx:latest
    container_name: rpi_home_nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ../nginx/conf.d:/etc/nginx/conf.d:ro
      - ../nginx/cert:/etc/ssl/private:ro
    networks:
      - internal
    depends_on:
      - app
      - homeassistant
      - webshare-search
    restart: unless-stopped

  db:
    image: mariadb:10.11
    container_name: rpi_home_db
    restart: unless-stopped
    volumes:
      - ../volumes/nextcloud/db:/var/lib/mysql
      - ../secrets:/run/secrets:ro
    environment:
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_ROOT_PASSWORD_FILE=/run/secrets/db_root_password
      - MYSQL_PASSWORD_FILE=/run/secrets/db_password
    networks:
      - internal

  app:
    image: nextcloud:stable
    container_name: rpi_home_nextcloud
    restart: unless-stopped
    depends_on:
      - db
    volumes:
      - ../volumes/nextcloud/html:/var/www/html
      - ../volumes/nextcloud/data:/var/www/html/data
      - ${VIDEO_PATH}:/var/www/html/data/${NEXTCLOUD_USER}/files/Videos
      - ${IMAGE_PATH}:/var/www/html/data/${NEXTCLOUD_USER}/files/Photos
      - ${DOC_PATH}:/var/www/html/data/${NEXTCLOUD_USER}/files/Documents
      - ../secrets:/run/secrets:ro
    user: "33:${MEDIA_GID:-1001}"  # www-data user with media group
    env_file:
      - .env
    environment:
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD_FILE=/run/secrets/db_password
      - MYSQL_HOST=db
      - OVERWRITEHOST=${HOSTNAME}
      - OVERWRITEPROTOCOL=https
      - OVERWRITEWEBROOT=/nextcloud
      - TRUSTED_PROXIES=10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
      - NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_USER}
      - NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_PASSWORD}
      - NEXTCLOUD_TRUSTED_DOMAINS=${HOSTNAME}
    networks:
      - internal

  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: rpi_home_homeassistant
    network_mode: host
    volumes:
      - ../volumes/homeassistant/config:/config
      - ../volumes/homeassistant/data:/config/deps
      - /etc/localtime:/etc/localtime:ro
EOF

# Add USB devices if specified
if [ -n "$USB_DEVICES" ]; then
    echo "      # USB Serial devices for Home Assistant" >> "$SCRIPT_DIR/docker-compose.yml"
    IFS='|' read -ra DEVICES <<< "$USB_DEVICES"
    usb_counter=0
    acm_counter=0
    
    for device in "${DEVICES[@]}"; do
        if [ -n "$device" ] && [ -e "$device" ]; then
            # Get the actual device type from the host system
            host_device=$(basename $(readlink "$device") 2>/dev/null)
            
            # Assign container device based on host device type with separate counters
            if [[ "$host_device" =~ ^ttyACM ]]; then
                container_device="ttyACM${acm_counter}"
                acm_counter=$((acm_counter + 1))
            else
                container_device="ttyUSB${usb_counter}"
                usb_counter=$((usb_counter + 1))
            fi
            
            echo "      - $device:/dev/$container_device" >> "$SCRIPT_DIR/docker-compose.yml"
        fi
    done
fi

# Continue with the rest of the Home Assistant service
cat >> "$SCRIPT_DIR/docker-compose.yml" << 'EOF'
    env_file:
      - .env
    environment:
      - TZ=${TIMEZONE}
      - ENABLE_IPV6=false
    restart: unless-stopped
EOF

# Add privileged mode if USB devices are present
if [ -n "$USB_DEVICES" ]; then
    echo "    privileged: true" >> "$SCRIPT_DIR/docker-compose.yml"
fi

# Continue with remaining services
cat >> "$SCRIPT_DIR/docker-compose.yml" << 'EOF'

  jellyfin:
    image: linuxserver/jellyfin
    container_name: rpi_home_jellyfin
    ports:
      - "8096:8096/tcp"    # Web interface
      - "8920:8920/tcp"    # HTTPS (optional)
      - "7359:7359/udp"    # Auto-discovery
      - "1900:1900/udp"    # DLNA
    volumes:
      - ../volumes/jellyfin/config:/config
      - ../volumes/jellyfin/cache:/cache
      - ${VIDEO_PATH}:/media/videos:ro
    env_file:
      - .env
    environment:
      - PUID=${HOST_UID:-1000}
      - PGID=${MEDIA_GID:-1001}
      - TZ=${TIMEZONE}
      - JELLYFIN_PublishedServerUrl=http://${HOSTNAME}:8096
    networks:
      - internal
    restart: unless-stopped

  webshare-search:
    image: rpi_home_webshare-search
    container_name: rpi_home_webshare_search
    ports:
      - "5000:5000/tcp"
    volumes:
      - ${VIDEO_PATH}:/downloads
    env_file:
      - .env
    environment:
      - PORT=5000
      - DEBUG=false
      - DOWNLOAD_PATH=/downloads
    user: "${HOST_UID:-1000}:${MEDIA_GID:-1001}"  # Run with media group for proper file permissions
    networks:
      - internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  internal:
    driver: bridge
EOF

# Set executable permissions
chmod 644 "$SCRIPT_DIR/docker-compose.yml"

echo "✅ docker-compose.yml generated successfully!"
echo ""
echo "📋 Configuration summary:"
echo "  • Hostname: ${HOSTNAME}"
echo "  • Video path: ${VIDEO_PATH}"
echo "  • Image path: ${IMAGE_PATH}"
echo "  • Document path: ${DOC_PATH}"
echo "  • Nextcloud user: ${NEXTCLOUD_USER}"
echo "  • Timezone: ${TIMEZONE}"

# Report USB devices
if [ -n "$USB_DEVICES" ]; then
    IFS='|' read -ra DEVICES <<< "$USB_DEVICES"
    device_count=${#DEVICES[@]}
    echo "  • USB Serial devices: ✅ $device_count device(s) configured for Home Assistant"
    for device in "${DEVICES[@]}"; do
        if [ -n "$device" ]; then
            device_name=$(basename "$device" | cut -d'-' -f2- | cut -d'_' -f1-3 2>/dev/null || echo "Unknown")
            echo "    - $device_name"
        fi
    done
else
    echo "  • USB Serial devices: ⚠️  None selected"
fi

echo ""
echo "🔍 Validate with: docker compose config"