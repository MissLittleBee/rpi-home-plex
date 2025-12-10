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
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_CODENAME=$VERSION_CODENAME
    else
        echo "Cannot detect OS. Trying generic installation..."
        OS="unknown"
    fi
    
    echo "Detected OS: $OS ($VERSION_CODENAME)"
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Choose installation method based on OS
    if [ "$OS" = "debian" ]; then
        echo "Installing Docker for Debian..."
        
        # Add Docker's official GPG key for Debian
        sudo mkdir -m 0755 -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up Debian repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        sudo apt-get update
        
        # Check if Docker CE is available, otherwise use docker.io from Debian repos
        if sudo apt-cache show docker-ce >/dev/null 2>&1; then
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        else
            echo "Docker CE not available, installing docker.io from Debian repositories..."
            sudo apt-get install -y docker.io docker-compose
        fi
        
    elif [ "$OS" = "ubuntu" ]; then
        echo "Installing Docker for Ubuntu..."
        
        # Add Docker's official GPG key for Ubuntu
        sudo mkdir -m 0755 -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up Ubuntu repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    else
        echo "Unsupported OS or OS detection failed. Trying generic installation..."
        # Fallback to distribution packages
        sudo apt-get install -y docker.io docker-compose || {
            echo "Failed to install Docker. Please install Docker manually."
            echo "See: https://docs.docker.com/engine/install/"
            return 1
        }
    fi
    
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
    # Check if user is in docker group but session hasn't refreshed
    if groups $USER | grep -q docker; then
        echo "⚠️  User is in docker group but session needs refresh. Using 'sg docker' to continue..."
        
        # Re-execute script with docker group privileges
        echo "Restarting script with docker group privileges..."
        exec sg docker -c "$0 $*"
    else
        echo ""
        echo "⚠️  Docker requires sudo access or user group membership."
        echo "Please run 'newgrp docker' or log out and back in, then try again."
        echo "Alternatively, run this script with sudo (not recommended for security)."
        exit 1
    fi
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
    read -p "Hostname/Domain [my.local]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-my.local}
    
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
    echo "🎬 Plex Media Server Configuration:"
    echo "To link your Plex server to your account, you need a claim token."
    echo "Get your claim token from: https://www.plex.tv/claim/"
    echo "(Token is valid for 4 minutes, so get it just before entering it here)"
    echo "Note: Token will be automatically removed from .env file after setup for security"
    read -p "Plex claim token (optional, press Enter to skip): " PLEX_CLAIM_TOKEN
    
    if [ -n "$PLEX_CLAIM_TOKEN" ]; then
        echo "✓ Plex claim token entered (will be used to link server to your account)"
    else
        echo "ℹ️  No claim token provided - you can manually claim the server later through Plex web interface"
    fi
    
    echo ""
    echo "📁 Storage Configuration:"
    
    # Get current user for default paths
    CURRENT_USER="${USER:-$(whoami)}"
    
    read -p "Video directory path [/home/$CURRENT_USER/videos]: " VIDEO_PATH
    VIDEO_PATH=${VIDEO_PATH:-/home/$CURRENT_USER/videos}
    
    # Plex library subdirectories (Movies and Series)
    read -p "Movies subdirectory name [movies]: " MOVIES_SUBDIR
    MOVIES_SUBDIR=${MOVIES_SUBDIR:-movies}
    MOVIES_PATH="$VIDEO_PATH/$MOVIES_SUBDIR"
    
    read -p "Series subdirectory name [series]: " SERIES_SUBDIR
    SERIES_SUBDIR=${SERIES_SUBDIR:-series}
    SERIES_PATH="$VIDEO_PATH/$SERIES_SUBDIR"
    
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
    
    # Create Plex subdirectories for Movies and Series
    for plex_subdir in "$MOVIES_PATH" "$SERIES_PATH"; do
        if [ ! -d "$plex_subdir" ]; then
            echo "Creating Plex directory: $plex_subdir"
            mkdir -p "$plex_subdir"
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
    echo "  Movies Path: $MOVIES_PATH"
    echo "  Series Path: $SERIES_PATH"
    echo "  Image Path: $IMAGE_PATH"
    echo "  Document Path: $DOC_PATH"
    echo "  Nextcloud User: $NEXTCLOUD_USER"
    echo "  Nextcloud Password: ✓ Set"
    echo "  Plex Claim Token: $([ -n "$PLEX_CLAIM_TOKEN" ] && echo '✓ Provided' || echo 'Not provided')"
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

# Plex Configuration
PLEX_CLAIM_TOKEN=$PLEX_CLAIM_TOKEN

# Storage Configuration
VIDEO_PATH=$VIDEO_PATH
MOVIES_PATH=$MOVIES_PATH
SERIES_PATH=$SERIES_PATH
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
    echo ""
    echo "🔧 Configuration Setup Required"
    if [ "$1" == "--reconfigure" ]; then
        echo "  Reconfiguring as requested..."
    else
        echo "  No existing configuration found - running initial setup..."
    fi
    setup_configuration
else
    echo ""
    echo "🚀 Quick Restart Mode"
    echo "✓ Using existing tools/.env configuration"
    echo "  - Skipping interactive setup (configuration already exists)"
    echo "  - Preserving existing Plex configuration and claim status"
    echo "  - Reusing existing nginx and docker-compose configurations"
    echo ""
    echo "💡 Restart Workflow Options:"
    echo "  - Quick restart: './home_stop.sh' (keep config) → './home_start.sh'"
    echo "  - Fresh setup: './home_stop.sh' (remove config) → './home_start.sh'"
    echo "  - Reconfigure: './home_start.sh --reconfigure'"
    echo ""
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
for dir in ./nginx/conf.d ./nginx/cert ./volumes/nextcloud/db ./volumes/nextcloud/html ./volumes/nextcloud/data ./volumes/homeassistant/config ./volumes/plex/config ./volumes/plex/transcode ./volumes/webshare; do
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

# Set secure permissions (handle existing files with different ownership)
if ! chmod 600 secrets/db_* 2>/dev/null; then
    echo "Using existing secret files with current permissions (owned by different user)"
else
    echo "Secret file permissions updated"
fi
echo "Secret files ready."

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
    
    # Create and setup movies and series subdirectories
    MOVIES_DIR="${DETECTED_VIDEO_PATH}/movies"
    SERIES_DIR="${DETECTED_VIDEO_PATH}/series"
    
    if [ ! -d "$MOVIES_DIR" ]; then
        echo "Creating movies directory: $MOVIES_DIR"
        mkdir -p "$MOVIES_DIR"
    fi
    
    if [ ! -d "$SERIES_DIR" ]; then
        echo "Creating series directory: $SERIES_DIR"
        mkdir -p "$SERIES_DIR"
    fi
    
    setup_directory_permissions "$MOVIES_DIR" "movies"
    setup_directory_permissions "$SERIES_DIR" "series"
    
    setup_directory_permissions "$DETECTED_IMAGE_PATH" "image" 
    setup_directory_permissions "$DETECTED_DOC_PATH" "document"
    
    # Setup Plex subdirectories with proper permissions
    if [ -n "$MOVIES_PATH" ] && [ -d "$MOVIES_PATH" ]; then
        echo "Setting up Movies directory permissions..."
        sudo chown -R $CURRENT_UID:$MEDIA_GID "$MOVIES_PATH"
        sudo chmod -R 775 "$MOVIES_PATH"
        sudo chmod g+s "$MOVIES_PATH"
        echo "✓ Movies directory: $MOVIES_PATH"
    fi
    
    if [ -n "$SERIES_PATH" ] && [ -d "$SERIES_PATH" ]; then
        echo "Setting up Series directory permissions..."
        sudo chown -R $CURRENT_UID:$MEDIA_GID "$SERIES_PATH"
        sudo chmod -R 775 "$SERIES_PATH"
        sudo chmod g+s "$SERIES_PATH"
        echo "✓ Series directory: $SERIES_PATH"
    fi
    
    # Fix Nextcloud volume permissions (www-data user with media group)
    echo "Setting up Nextcloud volume permissions..."
    if [ -d "volumes/nextcloud/html" ] || [ -d "volumes/nextcloud/data" ]; then
        sudo chown -R 33:$MEDIA_GID volumes/nextcloud/html volumes/nextcloud/data 2>/dev/null || true
        sudo chmod -R g+w volumes/nextcloud/html volumes/nextcloud/data 2>/dev/null || true
        echo "✓ Nextcloud volumes configured for www-data user with media group"
    fi
    
    # Home Assistant uses internal config directory - no separate data volume needed
    
    echo "✅ Storage permissions configured for shared access"
    
    # Export variables for docker-compose
    export MEDIA_GID
    export HOST_UID="$CURRENT_UID"
    export VIDEO_PATH="$DETECTED_VIDEO_PATH"
    export MOVIES_PATH
    export SERIES_PATH
    export IMAGE_PATH="$DETECTED_IMAGE_PATH" 
    export DOC_PATH="$DETECTED_DOC_PATH"
    
    echo "Exported variables for docker-compose:"
    echo "  MEDIA_GID=$MEDIA_GID"
    echo "  HOST_UID=$CURRENT_UID"
    echo "  VIDEO_PATH=$DETECTED_VIDEO_PATH"
    echo "  MOVIES_PATH=$MOVIES_PATH"
    echo "  SERIES_PATH=$SERIES_PATH"
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

# Generate nginx configuration files if needed
if [ ! -f "nginx/conf.d/default.conf" ] || [ "tools/.env" -nt "nginx/conf.d/default.conf" ]; then
    echo "🔧 Generating nginx configuration..."
    ./tools/generate_nginx_config.sh
else
    echo "✅ Quick Restart: nginx configuration is up to date (using existing configuration)"
fi

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
    echo "🔧 Generating docker-compose.yml configuration..."
    ./tools/generate_yml.sh
else
    echo "✅ Quick Restart: docker-compose.yml is up to date (using existing configuration)"
    echo "  - Preserving all existing service configurations"
    echo "  - Plex claim token handling: skipped (already configured)"
fi

# Deploy docker-compose services
echo "Starting Docker Compose services..."
cd tools
docker compose up -d
cd ..

echo "Services started successfully."

# Clean up Plex claim token after successful deployment (security best practice)
if [ -n "$PLEX_CLAIM_TOKEN" ] && [ -f "tools/.env" ]; then
    echo "Cleaning up Plex claim token from .env file for security..."
    sleep 30  # Give Plex container time to use the token
    sed -i '/^PLEX_CLAIM_TOKEN=/d' tools/.env
    echo "✓ Plex claim token removed from .env file (server should now be claimed)"
fi

# Wait for services to start and check status
echo "Waiting for services to initialize..."
sleep 15

# Set up automation systems (after services are stable)
echo "Waiting for services to stabilize before setting up automation..."
sleep 30

# Verify services are running before setting up automation
STABLE_SERVICES=$(docker ps --filter "status=running" | grep -c "Up")

if [ "$STABLE_SERVICES" -ge 6 ]; then  # All 6 services should be running (nginx, db, nextcloud, homeassistant, plex, webshare)
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
@reboot sleep 300 && ${CURRENT_DIR}/tools/scheduled-backup.sh
0 2 * * * ${CURRENT_DIR}/tools/scheduled-backup.sh
@reboot sleep 300 && ${CURRENT_DIR}/tools/scheduled-backup.sh
0 2 * * * ${CURRENT_DIR}/tools/scheduled-backup.sh
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
echo "  • Plex Media Server: https://${HOSTNAME}/plex/"
echo "  • Webshare Search: https://${HOSTNAME}/ws/ (or http://${HOSTNAME}:5000/)"
echo ""
echo "🔄 Automation features:"
echo "  • Libraries sync every 10 minutes automatically (cron)"
echo "  • Docker cleanup runs every 6 hours automatically (cron)"  
echo "  • Both systems restart automatically on reboot"
echo "  • New downloads appear in both Nextcloud and Plex"
echo "  • Check sync logs: tail -f logs/scheduled-sync.log"
echo "  • Check cleanup logs: tail -f logs/scheduled-cleanup.log"
echo "  • View all cron jobs: crontab -l"
echo "  • Manual sync: ./tools/scheduled-sync.sh"
echo "  • Manual cleanup: ./tools/scheduled-cleanup.sh"
echo ""
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
echo "    - Movies subdir: ${MOVIES_PATH:-not detected}"
echo "    - Series subdir: ${SERIES_PATH:-not detected}"
echo "  • Image path: ${DETECTED_IMAGE_PATH:-not detected}"
echo "  • Document path: ${DETECTED_DOC_PATH:-not detected}"
echo "  • Config file: $([ -f "$SCRIPT_DIR/config" ] && echo "config" || echo "tools/.env or auto-detected")"
echo ""
echo "🎬 Plex Network Access:"
echo "  • Reverse Proxy (Web): https://${HOSTNAME}/plex/ - Optimized for local network detection"
echo "  • Direct Access (Apps): http://${SERVER_IP}:32400 - For mobile apps, smart TVs, game consoles"
echo "  • Auto-discovery: Devices on your network will find Plex automatically"
echo "  • Both access methods support full streaming quality and local network features"
echo ""
echo "🎬 PLEX SETUP:"
echo "  1. Go to: https://${HOSTNAME}/plex/ or http://${SERVER_IP}:32400/web"
echo "  2. Sign in with your Plex account"
echo "  3. Name your server (e.g., 'Home Server')"
echo "  4. Add library: Movies -> Browse for folder -> /media/videos/movies"
echo "  5. Add library: TV Shows -> Browse for folder -> /media/videos/series"
echo ""
echo "🔍 Test webshare search and download at https://${HOSTNAME}/ws/"
echo "📝 Manual Setup Instructions:"
echo ""
echo "🌩️  NEXTCLOUD SETUP:"
echo "  1. Go to: https://${HOSTNAME}/nextcloud/"
echo "  2. Create admin account with any username/password you prefer"
echo "  3. Database configuration:"
echo "     Database & user: nextcloud"
echo "     Database password: $(cat secrets/db_password 2>/dev/null || echo '[password from secrets/db_password]')"
echo "     Database host: db"
echo "     Leave other fields as default"
echo "  4. Click 'Finish setup'"
echo "⚠️  Common Issues:"
echo "  • Downloaded files not visible in Nextcloud/Plex: Run ./tools/scheduled-cleanup.sh cleanup"
echo "  • Plex shows 'Remote Access' in web browser: check if Plex use hostname network"
echo "  • Webshare 'File temporarily unavailable': This is from webshare.cz servers,"
echo "    not our application. Try again later or choose a different file."
echo "  • SSL certificate warnings: Expected for self-signed certificates, mobile apps may warn, if it possible and safe go over this warning"
echo "  • Services starting slowly: Give containers 1-2 minutes to fully initialize"
