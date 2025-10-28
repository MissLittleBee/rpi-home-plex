#!/bin/bash
# fix_homeassistant.sh - Fix common Home Assistant configuration issues

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Home Assistant Configuration Fixer ==="

# Function to create missing YAML files
create_yaml_files() {
    echo "Checking required YAML configuration files..."
    
    # Create automations.yaml if missing
    if [ ! -f "./volumes/homeassistant/config/automations.yaml" ]; then
        echo "✓ Creating missing automations.yaml"
        cat > "./volumes/homeassistant/config/automations.yaml" << EOF
# Automations configuration
# Add your automations here
EOF
    else
        echo "✓ automations.yaml exists"
    fi
    
    # Create scripts.yaml if missing
    if [ ! -f "./volumes/homeassistant/config/scripts.yaml" ]; then
        echo "✓ Creating missing scripts.yaml"
        cat > "./volumes/homeassistant/config/scripts.yaml" << EOF
# Scripts configuration
# Add your scripts here
EOF
    else
        echo "✓ scripts.yaml exists"
    fi
    
    # Create scenes.yaml if missing
    if [ ! -f "./volumes/homeassistant/config/scenes.yaml" ]; then
        echo "✓ Creating missing scenes.yaml"
        cat > "./volumes/homeassistant/config/scenes.yaml" << EOF
# Scenes configuration
# Add your scenes here
EOF
    else
        echo "✓ scenes.yaml exists"
    fi
}

# Function to fix proxy configuration
fix_proxy_config() {
    echo "Updating Home Assistant proxy configuration..."
    
    # Get current Docker network info
    NETWORK_INFO=$(docker network inspect rpi_home_internal 2>/dev/null | jq -r '.[0].IPAM.Config[0].Subnet' 2>/dev/null || echo "10.0.1.0/24")
    
    cat > "./volumes/homeassistant/config/configuration.yaml" << EOF
# Loads default set of integrations. Do not remove.
default_config:

# HTTP integration configuration for reverse proxy
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.0.0.0/8
    - 172.16.0.0/12
    - 192.168.0.0/16
    - 127.0.0.1
    - ::1
    - ${NETWORK_INFO}

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF
    
    echo "✓ Configuration updated with trusted proxy: ${NETWORK_INFO}"
}

# Function to restart Home Assistant service
restart_homeassistant() {
    echo "Restarting Home Assistant service..."
    
    if docker compose -f docker-compose.yml ps homeassistant -q | grep -q .; then
        docker compose -f docker-compose.yml restart homeassistant
        echo "✓ Home Assistant service restarted"
        
        echo "Waiting for Home Assistant to start..."
        sleep 15
        
        # Check if service is running
        STATUS=$(docker compose -f docker-compose.yml ps homeassistant --format json | jq -r '.State')
        if [[ "$STATUS" == "running" ]]; then
            echo "✅ Home Assistant service is running after restart"
        else
            echo "⚠️  Home Assistant may still be starting. Check logs with: docker compose -f docker-compose.yml logs homeassistant"
        fi
    else
        echo "❌ Home Assistant service not found. Make sure the stack is running."
        exit 1
    fi
}

# Main execution
if [ "$1" = "--setup-only" ]; then
    echo "Setting up Home Assistant configuration files (setup mode)..."
    create_yaml_files
    fix_proxy_config
    echo "✓ Home Assistant configuration files created/updated"
else
    echo "Fixing Home Assistant configuration issues..."
    create_yaml_files
    fix_proxy_config
    restart_homeassistant

    echo ""
    echo "🎉 Home Assistant configuration fixes applied!"
    echo ""
    echo "📋 Access your Home Assistant:"
    echo "  • URL: https://ha.local/"
    echo "  • Check logs: docker compose -f docker-compose.yml logs homeassistant"
    echo "  • Service status: docker compose -f docker-compose.yml ps homeassistant"
fi