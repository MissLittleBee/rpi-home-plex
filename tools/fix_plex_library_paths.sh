#!/bin/bash

# Script to fix Plex library paths after NVME migration
# This updates the library paths to use container paths instead of host paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

if [ -z "$PLEX_TOKEN" ]; then
    echo "ERROR: PLEX_TOKEN not configured in .env"
    exit 1
fi

PLEX_URL="http://localhost:32400"

echo "Fixing Plex library paths..."
echo ""

# Function to delete and re-add library location
fix_library_path() {
    local section_id=$1
    local section_name=$2
    local old_path=$3
    local new_path=$4
    local library_type=$5
    
    echo "Processing library: $section_name (ID: $section_id)"
    echo "  Old path: $old_path"
    echo "  New path: $new_path"
    
    # Delete the library section
    echo "  Deleting old library..."
    curl -s -X DELETE "${PLEX_URL}/library/sections/${section_id}?X-Plex-Token=${PLEX_TOKEN}" >/dev/null
    
    sleep 2
    
    # Recreate the library with correct path
    echo "  Creating new library with correct path..."
    if [ "$library_type" == "movie" ]; then
        curl -s -X POST "${PLEX_URL}/library/sections?name=${section_name}&type=movie&agent=tv.plex.agents.movie&scanner=Plex%20Movie&language=cs-CZ&location=${new_path}&X-Plex-Token=${PLEX_TOKEN}" >/dev/null
    else
        curl -s -X POST "${PLEX_URL}/library/sections?name=${section_name}&type=show&agent=tv.plex.agents.series&scanner=Plex%20TV%20Series&language=cs-CZ&location=${new_path}&X-Plex-Token=${PLEX_TOKEN}" >/dev/null
    fi
    
    echo "  ✓ Library fixed"
    echo ""
}

# Fix Movies library (Filmy)
fix_library_path "1" "Filmy" "/mnt/data/together/movies/Filmy" "/media/videos/Filmy" "movie"

# Fix TV Shows library (Seriály)
fix_library_path "2" "Seriály" "/mnt/data/together/movies/Seriály" "/media/videos/Seriály" "show"

echo "Library paths have been fixed!"
echo "Plex will now scan the libraries. This may take a few minutes."
echo ""
echo "Check progress at: https://rpi.local/plex/web"
