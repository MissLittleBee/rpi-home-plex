#!/bin/bash
# validate_config.sh - Validate configuration and show current settings

set -e

# Get project root directory
PROJECT_ROOT="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
# Get script directory  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "❌ Configuration file (.env) not found!"
    echo "Run ./home_start.sh to set up configuration."
    exit 1
fi

# Load configuration
source "$SCRIPT_DIR/.env"

echo "=== 🔍 Current Configuration ==="
echo ""

echo "📡 Network Settings:"
echo "  Hostname: ${HOSTNAME:-❌ Not set}"
echo "  Server IP: ${SERVER_IP:-❌ Not set}"
echo "  VPN IP: ${VPN_IP:-❌ Not set}"
echo ""

echo "🔍 Webshare Configuration:"
echo "  Username: ${WEBSHARE_USERNAME:-❌ Not set}"
if [ -n "$WEBSHARE_PASSWORD" ]; then
    echo "  Password: ✓ Set"
else
    echo "  Password: ❌ Not set"
fi
echo ""

echo "📁 Storage Settings:"
echo "  Video Path: ${VIDEO_PATH:-❌ Not set}"
if [ -n "$VIDEO_PATH" ] && [ -d "$VIDEO_PATH" ]; then
    echo "    Status: ✓ Exists"
    echo "    Permissions: $(ls -ld "$VIDEO_PATH" | awk '{print $1, $3, $4}')"
else
    echo "    Status: ❌ Does not exist"
fi

echo "  Image Path: ${IMAGE_PATH:-❌ Not set}"
if [ -n "$IMAGE_PATH" ] && [ -d "$IMAGE_PATH" ]; then
    echo "    Status: ✓ Exists"
    echo "    Permissions: $(ls -ld "$IMAGE_PATH" | awk '{print $1, $3, $4}')"
else
    echo "    Status: ❌ Does not exist"
fi

echo "  Document Path: ${DOC_PATH:-❌ Not set}"
if [ -n "$DOC_PATH" ] && [ -d "$DOC_PATH" ]; then
    echo "    Status: ✓ Exists"
    echo "    Permissions: $(ls -ld "$DOC_PATH" | awk '{print $1, $3, $4}')"
else
    echo "    Status: ❌ Does not exist"
fi

# Check media group configuration
echo "  Media Group: ${MEDIA_GROUP_NAME:-media}"
if getent group "${MEDIA_GROUP_NAME:-media}" >/dev/null 2>&1; then
    MEDIA_GID=$(getent group "${MEDIA_GROUP_NAME:-media}" | cut -d: -f3)
    echo "    Status: ✓ Exists (GID: $MEDIA_GID)"
else
    echo "    Status: ❌ Does not exist"
fi
echo ""

echo "👤 Nextcloud Settings:"
echo "  Admin Username: ${NEXTCLOUD_USER:-❌ Not set}"
if [ -n "$NEXTCLOUD_PASSWORD" ]; then
    echo "  Admin Password: ✓ Set"
else
    echo "  Admin Password: ❌ Not set"
fi
echo ""

echo "🌍 System Settings:"
echo "  Timezone: ${TIMEZONE:-❌ Not set}"
echo "  Current User: $(whoami) (UID: $(id -u))"
if groups | grep -q "${MEDIA_GROUP_NAME:-media}"; then
    echo "  Media Group Membership: ✓ User is in ${MEDIA_GROUP_NAME:-media} group"
else
    echo "  Media Group Membership: ⚠️  User not in ${MEDIA_GROUP_NAME:-media} group"
fi
echo ""

echo "🔗 Service URLs:"
echo "  Home Assistant: https://${HOSTNAME}/"
echo "  Nextcloud: https://${HOSTNAME}/nextcloud/"  
echo "  Plex Media Server: https://${HOSTNAME}/plex/"
echo "  Webshare Search: https://${HOSTNAME}/ws/"
echo ""

# Validate required settings
ERRORS=0

if [ -z "$HOSTNAME" ]; then
    echo "❌ HOSTNAME not configured"
    ERRORS=$((ERRORS + 1))
fi

if [ -z "$SERVER_IP" ]; then
    echo "❌ SERVER_IP not configured"
    ERRORS=$((ERRORS + 1))
fi

if [ -z "$WEBSHARE_USERNAME" ] || [ -z "$WEBSHARE_PASSWORD" ]; then
    echo "❌ Webshare credentials not configured"
    ERRORS=$((ERRORS + 1))
fi

if [ -z "$VIDEO_PATH" ]; then
    echo "❌ VIDEO_PATH not configured"
    ERRORS=$((ERRORS + 1))
elif [ ! -d "$VIDEO_PATH" ]; then
    echo "❌ Video directory does not exist: $VIDEO_PATH"
    ERRORS=$((ERRORS + 1))
fi

if [ -z "$IMAGE_PATH" ]; then
    echo "❌ IMAGE_PATH not configured"
    ERRORS=$((ERRORS + 1))
elif [ ! -d "$IMAGE_PATH" ]; then
    echo "❌ Image directory does not exist: $IMAGE_PATH"
    ERRORS=$((ERRORS + 1))
fi

if [ -z "$DOC_PATH" ]; then
    echo "❌ DOC_PATH not configured"
    ERRORS=$((ERRORS + 1))
elif [ ! -d "$DOC_PATH" ]; then
    echo "❌ Document directory does not exist: $DOC_PATH"
    ERRORS=$((ERRORS + 1))
fi

# Validate media group exists
if ! getent group "${MEDIA_GROUP_NAME:-media}" >/dev/null 2>&1; then
    echo "❌ Media group '${MEDIA_GROUP_NAME:-media}' does not exist"
    ERRORS=$((ERRORS + 1))
fi

if [ -z "$NEXTCLOUD_USER" ]; then
    echo "❌ NEXTCLOUD_USER not configured"
    ERRORS=$((ERRORS + 1))
fi

if [ -z "$NEXTCLOUD_PASSWORD" ]; then
    echo "❌ NEXTCLOUD_PASSWORD not configured"
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
    echo "✅ Configuration is valid!"
    echo ""
    echo "🚀 Ready to deploy with: ./home_start.sh"
else
    echo ""
    echo "⚠️  Found $ERRORS configuration error(s)."
    echo "Run: ./home_start.sh --reconfigure"
fi