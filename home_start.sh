#!/bin/bash
# home_start.sh: Initialize Docker Swarm, create secrets, and start docker-compose services

set -e

echo "=== Home Server Stack Deployment ==="

# Load configuration from config file or .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config" ]; then
    echo "Loading configuration from config file..."
    source "$SCRIPT_DIR/config"
elif [ -f "$SCRIPT_DIR/tools/.env" ]; then
    echo "Loading configuration from tools/.env file..."
    source "$SCRIPT_DIR/tools/.env"
else
    echo "⚠️  No configuration file found. Please copy config.example to config and customize it."
    echo "Proceeding with default/detected values..."
fi

echo "Checking and installing prerequisites..."

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Set up repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    echo "Docker installed successfully!"
    echo "NOTE: You may need to log out and back in for group changes to take effect."
}

# Check for Docker
if ! command_exists docker; then
    echo "Docker not found. Installing Docker..."
    install_docker
else
    echo "✓ Docker is installed"
    
    # Check if Docker service is running
    if ! sudo systemctl is-active --quiet docker; then
        echo "Starting Docker service..."
        sudo systemctl start docker
    fi
    
    # Check if user is in docker group
    if ! groups $USER | grep -q docker; then
        echo "Adding user to docker group..."
        sudo usermod -aG docker $USER
        echo "NOTE: You may need to log out and back in for group changes to take effect."
    fi
fi

# Check for openssl (needed for certificates)
if ! command_exists openssl; then
    echo "Installing openssl..."
    sudo apt-get update
    sudo apt-get install -y openssl
else
    echo "✓ OpenSSL is installed"
fi

# Check for curl (needed for health checks and installations)
if ! command_exists curl; then
    echo "Installing curl..."
    sudo apt-get update
    sudo apt-get install -y curl
else
    echo "✓ curl is installed"
fi

# Check for cron (needed for auto-sync)
if ! command_exists crontab; then
    echo "Installing cron..."
    sudo apt-get update
    sudo apt-get install -y cron
    sudo systemctl enable cron
    sudo systemctl start cron
else
    echo "✓ cron is installed"
fi

# Check for python3 (needed for episode renaming scripts)
if ! command_exists python3; then
    echo "Installing python3..."
    sudo apt-get update
    sudo apt-get install -y python3
else
    echo "✓ python3 is installed"
fi

# Verify Docker is accessible without sudo
if ! docker info >/dev/null 2>&1; then
    echo ""
    echo "⚠️  Docker requires sudo access or user group membership."
    echo "Please run 'newgrp docker' or log out and back in, then try again."
    echo "Alternatively, run this script with sudo (not recommended for security)."
    exit 1
fi

echo "All prerequisites satisfied!"
echo ""

# Interactive configuration setup
setup_configuration() {
    echo ""
    echo "=== 🏠 Home Server Configuration Setup ==="
    echo ""
    echo "This will configure your home server with custom settings."
    echo "Press Enter to use default values shown in [brackets]."
    echo ""
    
    # Domain/Hostname configuration
    echo "📡 Network Configuration:"
    read -p "Hostname/Domain [ha.local]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-ha.local}
    
    # Auto-detect IP address
    DEFAULT_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null || echo "192.168.1.100")
    read -p "Server IP address [$DEFAULT_IP]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-$DEFAULT_IP}
    
    # VPN IP (optional)
    read -p "VPN IP address (optional) [10.10.20.1]: " VPN_IP
    VPN_IP=${VPN_IP:-10.10.20.1}
    
    echo ""
    echo "🔍 Webshare.cz Configuration:"
    read -p "Webshare.cz username: " WEBSHARE_USERNAME
    while [ -z "$WEBSHARE_USERNAME" ]; do
        echo "Username is required!"
        read -p "Webshare.cz username: " WEBSHARE_USERNAME
    done
    
    read -s -p "Webshare.cz password: " WEBSHARE_PASSWORD
    echo ""
    while [ -z "$WEBSHARE_PASSWORD" ]; do
        echo "Password is required!"
        read -s -p "Webshare.cz password: " WEBSHARE_PASSWORD
        echo ""
    done
    
    echo ""
    echo "📁 Storage Configuration:"
    
    # Get current user for default paths
    CURRENT_USER="${USER:-$(whoami)}"
    
    read -p "Video directory path [/home/$CURRENT_USER/videos]: " VIDEO_PATH
    VIDEO_PATH=${VIDEO_PATH:-/home/$CURRENT_USER/videos}
    
    read -p "Image directory path [/home/$CURRENT_USER/images]: " IMAGE_PATH
    IMAGE_PATH=${IMAGE_PATH:-/home/$CURRENT_USER/images}
    
    read -p "Document directory path [/home/$CURRENT_USER/documents]: " DOC_PATH
    DOC_PATH=${DOC_PATH:-/home/$CURRENT_USER/documents}
    
    # Create storage directories if they don't exist
    for storage_path in "$VIDEO_PATH" "$IMAGE_PATH" "$DOC_PATH"; do
        if [ ! -d "$storage_path" ]; then
            echo "Creating directory: $storage_path"
            mkdir -p "$storage_path"
        fi
    done
    
    echo ""
    echo "👤 Nextcloud Configuration:"
    read -p "Nextcloud admin username [admin]: " NEXTCLOUD_USER
    NEXTCLOUD_USER=${NEXTCLOUD_USER:-admin}
    
    read -s -p "Nextcloud admin password: " NEXTCLOUD_PASSWORD
    echo ""
    while [ -z "$NEXTCLOUD_PASSWORD" ]; do
        echo "Password cannot be empty."
        read -s -p "Nextcloud admin password: " NEXTCLOUD_PASSWORD
        echo ""
    done
    
    echo ""
    echo "🌍 Timezone Configuration:"
    DEFAULT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Europe/Prague")
    read -p "Timezone [$DEFAULT_TZ]: " TIMEZONE
    TIMEZONE=${TIMEZONE:-$DEFAULT_TZ}
    
    echo ""
    echo "📊 Configuration Summary:"
    echo "  Hostname: $HOSTNAME"
    echo "  Server IP: $SERVER_IP"
    echo "  VPN IP: $VPN_IP"
    echo "  Webshare Username: $WEBSHARE_USERNAME"
    echo "  Video Path: $VIDEO_PATH"
    echo "  Image Path: $IMAGE_PATH"
    echo "  Document Path: $DOC_PATH"
    echo "  Nextcloud User: $NEXTCLOUD_USER"
    echo "  Nextcloud Password: ✓ Set"
    echo "  Timezone: $TIMEZONE"
    echo ""
    
    read -p "Is this configuration correct? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Configuration cancelled. Please run the script again."
        exit 1
    fi
    
    # Create .env file in tools directory
    echo "Creating configuration files..."
    cat > tools/.env << EOF
# Network Configuration
HOSTNAME=$HOSTNAME
SERVER_IP=$SERVER_IP
VPN_IP=$VPN_IP

# Webshare.cz Configuration  
WEBSHARE_USERNAME=$WEBSHARE_USERNAME
WEBSHARE_PASSWORD=$WEBSHARE_PASSWORD

# Storage Configuration
VIDEO_PATH=$VIDEO_PATH
IMAGE_PATH=$IMAGE_PATH
DOC_PATH=$DOC_PATH

# Nextcloud Configuration
NEXTCLOUD_USER=$NEXTCLOUD_USER
NEXTCLOUD_PASSWORD=$NEXTCLOUD_PASSWORD

# System Configuration
TIMEZONE=$TIMEZONE
EOF
    
    echo "✓ Configuration saved to tools/.env file"
    
    # Validate .env file was created
    if [ ! -f "tools/.env" ]; then
        echo "❌ Failed to create .env file"
        exit 1
    fi
}

# Check if configuration exists or run interactive setup
if [ ! -f "tools/.env" ] || [ "$1" == "--reconfigure" ]; then
    setup_configuration
else
    echo "✓ Using existing tools/.env configuration"
    echo "  Run with --reconfigure to change settings"
fi

# Load configuration
source tools/.env

# Validate required variables
if [ -z "$WEBSHARE_USERNAME" ] || [ -z "$WEBSHARE_PASSWORD" ] || [ -z "$HOSTNAME" ]; then
    echo "⚠️  Configuration incomplete. Please run with --reconfigure"
    exit 1
fi

echo "✓ Configuration files verified"

# USB Serial Device Detection for Home Assistant
detect_usb_devices() {
    echo ""
    echo "🔌 USB Serial Device Detection for Home Assistant:"
    
    # Check if /dev/serial/by-id/ exists and has devices
    if [ ! -d "/dev/serial/by-id/" ]; then
        echo "  ℹ️  No USB serial devices directory found"
        return
    fi
    
    # Find USB serial devices
    USB_DEVICE_LIST=()
    while IFS= read -r -d '' device; do
        if [ -c "$device" ]; then  # Check if it's a character device
            USB_DEVICE_LIST+=("$device")
        fi
    done < <(find /dev/serial/by-id/ -name "*" -print0 2>/dev/null)
    
    if [ ${#USB_DEVICE_LIST[@]} -eq 0 ]; then
        echo "  ℹ️  No USB serial devices detected"
        return
    fi
    
    echo "  Found ${#USB_DEVICE_LIST[@]} USB serial device(s):"
    for i in "${!USB_DEVICE_LIST[@]}"; do
        device="${USB_DEVICE_LIST[$i]}"
        device_name=$(basename "$device")
        # Try to get a friendlier name
        friendly_name=$(echo "$device_name" | sed 's/usb-//g' | sed 's/_/ /g' | cut -d'-' -f1-3)
        echo "    $((i+1)). $friendly_name"
        echo "       Path: $device"
    done
    
    echo ""
    echo "These devices can be used by Home Assistant for:"
    echo "  • Zigbee coordinators (ConBee, Sonoff, etc.)"
    echo "  • Z-Wave controllers"
    echo "  • Serial sensors and devices"
    echo ""
    
    # Ask user which devices to add
    selected_devices=""
    read -p "Do you want to add any of these devices to Home Assistant? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Select devices to add (enter numbers separated by spaces, or 'all' for all devices):"
        read -p "Selection: " selection
        
        if [ "$selection" = "all" ]; then
            # Add all devices
            for device in "${USB_DEVICE_LIST[@]}"; do
                if [ -n "$selected_devices" ]; then
                    selected_devices="$selected_devices|$device"
                else
                    selected_devices="$device"
                fi
            done
        else
            # Add selected devices
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#USB_DEVICE_LIST[@]} ]; then
                    device="${USB_DEVICE_LIST[$((num-1))]}"
                    if [ -n "$selected_devices" ]; then
                        selected_devices="$selected_devices|$device"
                    else
                        selected_devices="$device"
                    fi
                fi
            done
        fi
        
        if [ -n "$selected_devices" ]; then
            # Add to .env file
            if grep -q "^USB_DEVICES=" tools/.env; then
                sed -i "s|^USB_DEVICES=.*|USB_DEVICES=$selected_devices|" tools/.env
            else
                echo "USB_DEVICES=$selected_devices" >> tools/.env
            fi
            echo "✅ Selected USB devices will be available to Home Assistant"
        else
            echo "ℹ️  No valid devices selected"
        fi
    else
        echo "ℹ️  Skipping USB device configuration"
        # Remove USB_DEVICES from .env if it exists
        sed -i '/^USB_DEVICES=/d' tools/.env 2>/dev/null || true
    fi
}

# Run USB device detection
detect_usb_devices

echo ""

# Ensure Docker is running (no swarm needed for compose)
echo "Checking Docker daemon status..."
if ! docker info >/dev/null 2>&1; then
    echo "Starting Docker service..."
    sudo systemctl start docker
fi

# Check and create folders for volumes if missing
for dir in ./nginx/conf.d ./nginx/cert ./volumes/nextcloud/db ./volumes/nextcloud/html ./volumes/nextcloud/data ./volumes/homeassistant/config ./volumes/jellyfin/config ./volumes/webshare; do
    if [ ! -d "$dir" ]; then
        echo "Creating missing directory: $dir"
        mkdir -p "$dir"
    else
        echo "Directory exists: $dir"
    fi
done

# Setup Home Assistant configuration files
echo "Setting up Home Assistant configuration..."
./tools/fix_homeassistant.sh --setup-only

# Generate SSL certificates if they don't exist
if [ ! -f "./nginx/cert/server.crt" ] || [ ! -f "./nginx/cert/server.key" ]; then
    echo "SSL certificates not found. Generating..."
    ./tools/create_ssl.sh
else
    echo "SSL certificates already exist."
fi

# Build webshare-search service
echo "Building webshare-search service..."
docker build -f tools/Dockerfile.webshare -t rpi_home_webshare-search .

# Generate random passwords for secrets files (no logging)
generate_secret() {
    openssl rand -base64 32
}

# Create or update secret files
echo "Creating/updating secret files..."
mkdir -p secrets

# Generate secrets only if they don't exist
if [ ! -f "secrets/db_root_password" ]; then
    generate_secret > secrets/db_root_password
fi
if [ ! -f "secrets/db_password" ]; then
    generate_secret > secrets/db_password
fi

# Set secure permissions
chmod 600 secrets/db_*
echo "Secret files created."

# Setup storage paths and permissions
setup_storage_permissions() {
    echo ""
    echo "📁 Storage Paths & Permissions Setup:"
    
    # Get current user and detect system configuration
    CURRENT_USER="${USER:-$(whoami)}"
    CURRENT_UID=$(id -u "$CURRENT_USER")
    MEDIA_GROUP_NAME="${MEDIA_GROUP_NAME:-media}"
    
    # Detect or prompt for storage paths
    detect_storage_paths() {
        # Video path detection
        if [ -n "$VIDEO_PATH" ]; then
            DETECTED_VIDEO_PATH="$VIDEO_PATH"
        elif [ -d "/home/$CURRENT_USER/videos" ]; then
            DETECTED_VIDEO_PATH="/home/$CURRENT_USER/videos"
        else
            DETECTED_VIDEO_PATH="/home/$CURRENT_USER/videos"
        fi
        
        # Image path detection  
        if [ -n "$IMAGE_PATH" ]; then
            DETECTED_IMAGE_PATH="$IMAGE_PATH"
        elif [ -d "/home/$CURRENT_USER/images" ]; then
            DETECTED_IMAGE_PATH="/home/$CURRENT_USER/images"
        else
            DETECTED_IMAGE_PATH="/home/$CURRENT_USER/images"
        fi
        
        # Document path detection
        if [ -n "$DOC_PATH" ]; then
            DETECTED_DOC_PATH="$DOC_PATH"
        elif [ -d "/home/$CURRENT_USER/documents" ]; then
            DETECTED_DOC_PATH="/home/$CURRENT_USER/documents"
        else
            DETECTED_DOC_PATH="/home/$CURRENT_USER/documents"
        fi
    }
    
    detect_storage_paths
    
    echo "Detected user: $CURRENT_USER (UID: $CURRENT_UID)"
    echo "Video directory: $DETECTED_VIDEO_PATH"
    echo "Image directory: $DETECTED_IMAGE_PATH"
    echo "Document directory: $DETECTED_DOC_PATH"
    echo "Media group: $MEDIA_GROUP_NAME"
    
    # Create media group if it doesn't exist
    if ! getent group "$MEDIA_GROUP_NAME" >/dev/null 2>&1; then
        echo "Creating '$MEDIA_GROUP_NAME' group..."
        sudo groupadd "$MEDIA_GROUP_NAME"
    fi
    
    # Get the media group ID for docker-compose updates
    MEDIA_GID=$(getent group "$MEDIA_GROUP_NAME" | cut -d: -f3)
    echo "Media group ID: $MEDIA_GID"
    
    # Add current user to media group
    echo "Adding users to media group..."
    sudo usermod -a -G "$MEDIA_GROUP_NAME" "$CURRENT_USER" >/dev/null 2>&1 || true
    
    # Add www-data to media group if it exists (for web services)
    if id www-data >/dev/null 2>&1; then
        sudo usermod -a -G "$MEDIA_GROUP_NAME" www-data >/dev/null 2>&1 || true
        echo "Added www-data to $MEDIA_GROUP_NAME group"
    fi
    
    # Create and set permissions on storage directories
    setup_directory_permissions() {
        local DIR_PATH="$1"
        local DIR_TYPE="$2"
        
        echo "Setting up $DIR_TYPE directory: $DIR_PATH"
        
        # Create directory if it doesn't exist
        if [ ! -d "$DIR_PATH" ]; then
            echo "Creating directory: $DIR_PATH"
            mkdir -p "$DIR_PATH"
        fi
        
        # Set ownership and permissions
        sudo chgrp -R "$MEDIA_GROUP_NAME" "$DIR_PATH"
        sudo chmod -R g+w "$DIR_PATH"
        sudo find "$DIR_PATH" -type d -exec chmod g+s {} \; 2>/dev/null || true
        
        # Set default file permissions (664 for files, 2775 for directories)
        sudo find "$DIR_PATH" -type f -exec chmod 664 {} \; 2>/dev/null || true
        sudo find "$DIR_PATH" -type d -exec chmod 2775 {} \; 2>/dev/null || true
    }
    
    # Setup all storage directories
    setup_directory_permissions "$DETECTED_VIDEO_PATH" "video"
    setup_directory_permissions "$DETECTED_IMAGE_PATH" "image" 
    setup_directory_permissions "$DETECTED_DOC_PATH" "document"
    
    echo "✅ Storage permissions configured for shared access"
    
    # Export variables for docker-compose
    export MEDIA_GID
    export HOST_UID="$CURRENT_UID"
    export VIDEO_PATH="$DETECTED_VIDEO_PATH"
    export IMAGE_PATH="$DETECTED_IMAGE_PATH" 
    export DOC_PATH="$DETECTED_DOC_PATH"
    
    echo "Exported variables for docker-compose:"
    echo "  MEDIA_GID=$MEDIA_GID"
    echo "  HOST_UID=$CURRENT_UID"
    echo "  VIDEO_PATH=$DETECTED_VIDEO_PATH"
    echo "  IMAGE_PATH=$DETECTED_IMAGE_PATH"
    echo "  DOC_PATH=$DETECTED_DOC_PATH"
    
    # Update .env file with calculated system variables
    echo "Updating .env file with system variables..."
    cat >> tools/.env << EOF

# System Variables (Auto-calculated)
HOST_UID=$CURRENT_UID
MEDIA_GID=$MEDIA_GID
EOF
}

# Run setup functions
setup_storage_permissions

# Generate nginx configuration files first
echo "Generating nginx configuration..."
./tools/generate_nginx_config.sh

# Validate configuration before deployment
echo "Validating configuration..."
if ! ./tools/validate_config.sh > /dev/null 2>&1; then
    echo "❌ Configuration validation failed. Please check your settings."
    ./tools/validate_config.sh
    exit 1
fi
echo "✓ Configuration validated successfully."

# Export environment variables for Docker Compose
export $(grep -v '^#' tools/.env | xargs)

# Also export USB_DEVICES if it exists
if grep -q "^USB_DEVICES=" tools/.env; then
    export USB_DEVICES=$(grep "^USB_DEVICES=" tools/.env | cut -d'=' -f2)
fi

# Generate docker-compose.yml if it doesn't exist or is outdated
if [ ! -f "tools/docker-compose.yml" ] || [ "tools/.env" -nt "tools/docker-compose.yml" ]; then
    echo "Generating docker-compose.yml configuration..."
    ./tools/generate_yml.sh
else
    echo "✓ docker-compose.yml is up to date"
fi

# Deploy docker-compose services
echo "Starting Docker Compose services..."
cd tools
docker compose up -d
cd ..

echo "Services started successfully."

# Wait for services to start and check status
echo "Waiting for services to initialize..."
sleep 15

# Set up automation systems (after services are stable)
echo "Waiting for services to stabilize before setting up automation..."
sleep 30

# Verify services are running before setting up automation
STABLE_SERVICES=$(docker compose -f tools/docker-compose.yml ps --format json | jq -r '.State' | grep -c "running" || echo "0")

if [ "$STABLE_SERVICES" -ge 5 ]; then  # All 5 services should be running
    echo "✓ Services are stable - setting up automation systems"
    
    # Set up auto-sync cron jobs
    echo "Setting up auto-sync system..."
    if command_exists crontab; then
        # Create logs directory
        mkdir -p logs
        
        # Get current directory for cron jobs
        CURRENT_DIR=$(pwd)
        
        # Set up cron jobs for both auto-sync and scheduled cleanup with absolute paths
        cat << CRONEOF | crontab -
@reboot sleep 300 && ${CURRENT_DIR}/tools/scheduled-sync.sh
*/10 * * * * ${CURRENT_DIR}/tools/scheduled-sync.sh
@reboot sleep 360 && ${CURRENT_DIR}/tools/scheduled-cleanup.sh
0 */6 * * * ${CURRENT_DIR}/tools/scheduled-cleanup.sh
CRONEOF
        
        echo "✓ Auto-sync cron jobs configured (every 10 minutes + on reboot)"
        echo "✓ Docker cleanup cron jobs configured (every 6 hours + on reboot)"
        
        # Trigger initial sync after services are ready
        echo "Triggering initial library sync..."
        ./tools/scheduled-sync.sh || echo "Initial sync will retry automatically"
    else
        echo "⚠️  cron not available - auto-sync will need to be configured manually"
    fi
else
    echo "⚠️  Services not fully stable yet - skipping automation setup"
    echo "  Set up manually when ready:"
    echo "    Auto-sync: Add cron jobs or run './home_start.sh' again"
    echo "    Cleanup: sudo ./tools/docker_cleanup.sh install"
fi



echo ""
echo "=== Deployment Complete! ==="
echo ""

# Check final service status
cd tools
RUNNING_SERVICES=$(docker compose ps --format json | jq -r '.State' | grep -c "running" || echo "0")
TOTAL_SERVICES=$(docker compose ps --services | wc -l)
cd ..

echo "📊 Service Status: $RUNNING_SERVICES/$TOTAL_SERVICES services running"
if [ "$RUNNING_SERVICES" -eq "$TOTAL_SERVICES" ]; then
    echo "✅ All services started successfully!"
else
    echo "⚠️  Some services may still be starting. Check with: docker compose -f tools/docker-compose.yml ps"
fi

echo ""
echo "🎉 Your home server stack is now running!"
echo ""
echo "📁 Access your services:"
echo "  • Home Assistant: https://${HOSTNAME}/"
echo "  • Nextcloud: https://${HOSTNAME}/nextcloud/"
echo "  • Jellyfin: https://${HOSTNAME}/jellyfin/"
echo "  • Webshare Search: https://${HOSTNAME}/ws/ (or http://${HOSTNAME}:5000/)"
echo ""
echo "🔄 Automation features:"
echo "  • Libraries sync every 10 minutes automatically (cron)"
echo "  • Docker cleanup runs every 6 hours automatically (cron)"  
echo "  • Both systems restart automatically on reboot"
echo "  • New downloads appear in both Nextcloud and Jellyfin"
echo "  • Check sync logs: tail -f logs/scheduled-sync.log"
echo "  • Check cleanup logs: tail -f logs/scheduled-cleanup.log"
echo "  • View all cron jobs: crontab -l"
echo "  • Manual sync: ./tools/scheduled-sync.sh"
echo "  • Manual cleanup: ./tools/scheduled-cleanup.sh"
echo ""
echo "📋 Next steps:"
echo "  1. Configure Nextcloud admin account at https://${HOSTNAME}/nextcloud/"
echo "  2. Set up Home Assistant at https://${HOSTNAME}/"
echo "  3. Add media to Jellyfin library at https://${HOSTNAME}/jellyfin/"
echo "  4. Test webshare search and download at https://${HOSTNAME}/ws/"
echo ""
echo "🔧 Troubleshooting:"
echo "  • Fix Home Assistant issues: ./tools/fix_homeassistant.sh"
echo "  • Fix storage permissions: ./tools/scheduled-cleanup.sh cleanup"
echo "  • Check service logs: docker compose -f tools/docker-compose.yml logs <service_name>"
echo "  • Validate configuration: ./tools/validate_config.sh"
echo ""
echo "⚙️  Configuration:"
echo "  • Current user: $(whoami) (UID: $(id -u))"
if getent group "${MEDIA_GROUP_NAME:-media}" >/dev/null 2>&1; then
    echo "  • Media group: ${MEDIA_GROUP_NAME:-media} (GID: $(getent group "${MEDIA_GROUP_NAME:-media}" | cut -d: -f3))"
else
    echo "  • Media group: not configured"
fi
echo "  • Video path: ${DETECTED_VIDEO_PATH:-not detected}"
echo "  • Image path: ${DETECTED_IMAGE_PATH:-not detected}"
echo "  • Document path: ${DETECTED_DOC_PATH:-not detected}"
echo "  • Config file: $([ -f "$SCRIPT_DIR/config" ] && echo "config" || echo "tools/.env or auto-detected")"
echo ""
echo "⚠️  Common Issues:"
echo "  • Downloaded files not visible in Nextcloud/Jellyfin: Run ./tools/scheduled-cleanup.sh cleanup"
echo "  • Webshare 'File temporarily unavailable': This is from webshare.cz servers,"
echo "    not our application. Try again later or choose a different file."
echo "  • SSL certificate warnings: Expected for self-signed certificates"
echo "  • Services starting slowly: Give containers 1-2 minutes to fully initialize"
