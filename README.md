# 🏠 RPi Home Server Stack

A complete Docker Compose-based home server solution providing file sharing, media streaming, home automation, SSL-secured reverse proxy access, and automated library synchronization.

## 📋 Overview

This project provides a **fully automated, zero-configuration** home server stack using Docker Compose. Simply run `./home_start.sh` and answer a few questions to deploy a complete media and home automation platform.

**🎯 Key Features:**
- **🚀 One-Command Deployment** - Interactive setup handles everything automatically
- **🔧 Zero Hardcoded Values** - Fully portable and configurable with validation
- **📁 Multi-Path Storage** - Separate directories for Videos, Images, and Documents
- **� Shared Permission System** - Media group ensures cross-service file access
- **📱 Mobile App Support** - Optimized nginx configuration for Nextcloud mobile apps
- **🔄 Unified Automation** - Sync every 10min, cleanup every 6h, both via cron
- **🔒 Security Built-In** - SSL certificates, secrets management, reverse proxy

**📦 Included Services:**
- **🔒 Nginx Reverse Proxy** - SSL-terminated proxy with dynamic configuration and mobile app support
- **☁️ Nextcloud** - Self-hosted file sharing and collaboration platform with multi-directory support (Videos, Images, Documents)
- **🏡 Home Assistant** - Home automation and IoT device management platform
- **🎬 Plex Media Server** - Professional media server with optimized reverse proxy configuration for local network detection
- **🔍 Webshare Search** - English web interface for searching and downloading from webshare.cz with real-time progress tracking
- **🗄️ MariaDB** - Database backend for Nextcloud
- **🔄 Automated Maintenance** - Scheduled sync (every 10 minutes) and Docker cleanup (every 6 hours)

## 🏗️ Architecture

```
Internet → Nginx (SSL) → Internal Services
                ├── Nextcloud (/nextcloud) ←──┐
                ├── Home Assistant (/)        │ Auto-Sync
                ├── Plex Media Server (/plex) ←┘ (Every 10min)
                └── Webshare Search (/ws)
```

### 🎬 Multi-Path Storage System

- **Organized Storage**: Separate directories for Videos, Images, and Documents
- **Shared Access**: All services access storage with proper `media` group permissions (GID 1001)
- **Automatic Permissions**: setgid directories ensure new files get correct group ownership
- **Scheduled Maintenance**: Permission fixes every 6 hours via automated cleanup
- **Multi-Library Support**: Plex serves both video and photo libraries with automatic metadata
- **Progress Tracking**: Real-time download progress bars with English interface
- **Cross-Platform Visibility**: Files automatically visible in Nextcloud, Plex, and mobile apps

## 🚀 Quick Start

### Prerequisites

- Ubuntu/Debian-based Linux system (tested on Raspberry Pi OS)
- Docker installed and running
- Domain name or local hostname (e.g., `ha.local`)

### 1. Clone Repository

```bash
git clone <your-gitlab-repo-url>
cd rpi_home
```

### 2. Deploy Everything

```bash
./home_start.sh
```

**That's it!** The `home_start.sh` script will:
- 🖥️ **Interactive Setup**: Ask for your configuration (hostname, IPs, webshare credentials, Nextcloud user, etc.)
- ✅ **Auto-Generate**: Create `tools/.env` file and nginx configuration
- ✅ **Setup Docker Environment**: Configure container orchestration
- ✅ **Create Secrets**: Generate secure random database passwords
- ✅ **Generate SSL Certificates**: Create certificates for your hostname/IPs
- ✅ **Validate Configuration**: Verify all settings before deployment
- ✅ **Deploy Services**: Start all containers with your custom configuration
- ✅ **Setup Auto-Sync**: Configure automatic library synchronization
- ✅ **Initial Sync**: Trigger first library sync and verify service status

### 4. Configuration Options

During setup, you'll be asked for:
- **Hostname/Domain** (e.g., `ha.local`, `myserver.com`)
- **Server IP Address** (auto-detected)
- **VPN IP Address** (optional, for VPN access)
- **Webshare.cz Credentials** (username and password)
- **Plex Claim Token** (optional, from https://www.plex.tv/claim/ - automatically removed after setup for security)
- **Storage Directory Paths**:
  - Video directory (default: `/home/user/videos`)
  - Image directory (default: `/home/user/images`)
  - Document directory (default: `/home/user/documents`)
- **Nextcloud Admin Username** (default: `admin`)
- **Timezone** (auto-detected from system)

### 4. Reconfigure Anytime

```bash
# Quick restart (preserves configuration)
./home_stop.sh && ./home_start.sh

# Change configuration
./home_start.sh --reconfigure

# Fresh setup (remove config)
./home_stop.sh  # Choose config removal
./home_start.sh

# Validate current config
./tools/validate_config.sh
```

### 5. Access Services

Services will be available at your configured hostname/IP:
- **Home Assistant**: `https://[your-hostname]/`
- **Nextcloud**: `https://[your-hostname]/nextcloud/`
- **Plex Media Server**: 
  - **Web Browser**: `https://[your-hostname]/plex/` (optimized for local network detection)
  - **Apps & Devices**: `http://[server-ip]:32400` (direct access for mobile apps, smart TVs)
- **Webshare Search**: `https://[your-hostname]/ws/`

All services are automatically configured with proper authentication and media library synchronization.

## 📁 Project Structure

```
rpi_home/
├── home_start.sh              # 🚀 Main deployment script (interactive setup)
├── home_stop.sh               # ⏹️ Stop all services
├── home_update.sh             # 🔄 Update and redeploy services
├── tools/                     # 🛠️ Utility scripts and configs
│   ├── .env                   # ⚙️ Configuration file (auto-generated)
│   ├── docker-compose.yml     # Main service definitions with multi-path storage
│   ├── Dockerfile.webshare    # Webshare app container build
│   ├── scheduled-sync.sh      # Efficient sync script (runs every 10min)
│   ├── scheduled-cleanup.sh   # Automated cleanup and permission fixes (runs every 6h)
│   ├── create_ssl.sh          # SSL certificate generator
│   ├── fix_homeassistant.sh   # Home Assistant configuration fixes
│   ├── generate_nginx_config.sh # Dynamic nginx config generator (with backup)
│   └── validate_config.sh     # Configuration validator (multi-path aware)
├── nginx/
│   ├── conf.d/
│   │   └── default.conf       # Reverse proxy configuration (auto-generated)
│   └── cert/                  # SSL certificates (auto-generated)
├── volumes/
│   ├── homeassistant/
│   │   ├── config/            # HA configuration files (tracked in Git)
│   │   └── data/              # HA runtime data (ignored)
│   ├── nextcloud/             # Nextcloud data (ignored)
│   ├── plex/                  # Plex data (ignored)
│   └── webshare/              # Webshare search application
├── logs/                      # 📄 Application logs
└── README.md                  # 📖 This documentation
```

## 🔧 Management Scripts

### Stack Management

```bash
# Start all services (fully automated setup)
./home_start.sh

# Stop all services with detailed cleanup options
./home_stop.sh

# Update and redeploy services
./home_update.sh
```

**home_start.sh Complete Workflow:**
1. Prerequisites check (Docker, OpenSSL, curl, cron, python3)
2. Interactive configuration setup
3. Docker environment setup
4. SSL certificate generation
5. Nginx configuration generation  
6. Configuration validation
7. Docker Compose deployment
8. Auto-sync setup and initial library sync
9. Service status verification

**🔄 Sync Management**

```bash
# Manual sync (triggers immediate Nextcloud + Plex refresh)
./tools/scheduled-sync.sh

# Check sync logs
tail -f logs/scheduled-sync.log

# View current cron jobs
crontab -l

# Validate current configuration
./tools/validate_config.sh
```

**Scheduled sync runs automatically every 10 minutes and after system reboot.**
Initial sync is triggered automatically during deployment. Uses efficient API-based approach with minimal resource usage.

### Automated Maintenance System

The system includes comprehensive automated maintenance:

```bash
# Run storage permission fixes and Docker cleanup manually
./tools/scheduled-cleanup.sh cleanup

# Check maintenance logs
tail -f logs/scheduled-cleanup.log

# View automation status (both sync and cleanup)
./tools/validate_config.sh
```

**Automated Maintenance Features:**
- **Docker Cleanup**: Removes unused containers, images, and networks every 6 hours
- **Permission Fixes**: Ensures all storage directories have correct media group ownership
- **Multi-Path Support**: Handles Videos, Images, and Documents directories separately
- **Cron Integration**: Unified with sync system for consistent scheduling

### Detailed Cleanup Information

The `./home_stop.sh` script provides detailed explanations of what will be cleaned when you choose cleanup options:

### Quick Restart Workflow

```bash
# Quick restart (preserves all configuration)
./home_stop.sh        # Choose "N" to keep config files
./home_start.sh       # Uses existing configuration, skips interactive setup

# Fresh setup (reconfigure everything)  
./home_stop.sh        # Choose "Y" to remove config files
./home_start.sh       # Runs full interactive setup

# Reconfigure without stopping
./home_start.sh --reconfigure
```

**Restart Options:**
- **Docker Resource Cleanup**: Removes unused networks, dangling images, build cache, and stopped containers while preserving your data and running services
- **Configuration Cleanup**: Option to remove config files for fresh setup or preserve for quick restart
- **Automation Cleanup**: Option to remove cron jobs while preserving sync scripts, logs, and media files

## ⚙️ Configuration

All configuration is stored in `tools/.env` and automatically generated during setup. No manual configuration files to edit!

### Configuration Management

**Centralized Configuration:**
- Single configuration file: `tools/.env`
- All services use environment variables from this file
- No hardcoded values anywhere in the system
- Automatic validation before deployment

**Configuration Contents:**
```bash
# Network Configuration
HOSTNAME=your.domain.com
SERVER_IP=192.168.1.100
VPN_IP=10.10.20.1

# Webshare.cz Configuration  
WEBSHARE_USERNAME=your_username
WEBSHARE_PASSWORD=your_password

# Plex Configuration
PLEX_CLAIM_TOKEN=claim-xxxxxxxxxxxx

# Storage Configuration
VIDEO_PATH=/path/to/your/videos
IMAGE_PATH=/path/to/your/images
DOC_PATH=/path/to/your/documents

# Nextcloud Configuration
NEXTCLOUD_USER=admin
NEXTCLOUD_PASSWORD=secure_password

# System Configuration
TIMEZONE=Europe/Prague
```

**Managing Configuration:**
```bash
# Reconfigure everything
./home_start.sh --reconfigure

# Validate current settings
./tools/validate_config.sh

# View current configuration
cat tools/.env
```

### Home Assistant

Configuration files are stored in `volumes/homeassistant/config/` and tracked in Git:
- `configuration.yaml` - Main configuration
- `automations.yaml` - Automation rules
- `scripts.yaml` - Custom scripts
- `scenes.yaml` - Scene definitions

Runtime data in `volumes/homeassistant/data/` is excluded from Git.

### Nextcloud

**Manual Setup Required**: For better control and reliability, Nextcloud uses manual setup through web interface.

🚀 **Fresh Installation Process:**
1. Access https://[your-hostname]/nextcloud/
2. **Create admin account** with your preferred username and password
3. **Database configuration** (automatically provided):
   - Database & user: `nextcloud`
   - Database password: Available in `secrets/db_password` file
   - Database host: `db`
   - Leave other fields as default
4. Click 'Finish setup'
5. **Media library ready** at the correct user path

**What's Pre-Configured:**
- ✅ Database connection: MariaDB backend with auto-generated secure passwords
- ✅ Trusted domains: Pre-configured for your `HOSTNAME`
- ✅ Storage mounts: Videos, Images, and Documents directories correctly mapped
- ✅ Reverse proxy: Ready for `/nextcloud/` path access
- ✅ SSL termination: Handled by nginx reverse proxy

**Setup Instructions**: Detailed database credentials and setup steps provided in deployment output.

**⚠️ Important**: This auto-setup only works on **first deployment**. If you already have Nextcloud data, you'll need to use existing credentials.

**To Reset Nextcloud** (if needed):
```bash
# Stop services and remove Nextcloud data
./home_stop.sh
sudo rm -rf volumes/nextcloud/
./home_start.sh  # Will trigger fresh auto-setup
```

### 🎬 Plex Media Server & Local Network Optimization

Media files are organized in separate directories with automated management:

**Dual Access Configuration:**
- **Reverse Proxy Web Access**: `https://[hostname]/plex/` - Optimized for local network detection with special headers
- **Direct Device Access**: `http://[server-ip]:32400` - For mobile apps, smart TVs, game consoles with auto-discovery
- **Local Network Recognition**: Reverse proxy connections treated as local for full streaming quality
- **Automatic Device Discovery**: DLNA and GDM ports exposed for seamless device connection

**Multi-Library Setup:**
- **Video Library**: `{VIDEO_PATH}` - Movies, TV shows, and video content
- **Photo Library**: `{IMAGE_PATH}` - Photos, screenshots, and image collections
- **Documents**: Available in Nextcloud at `{DOC_PATH}`

**Permission System:**
- **Media Group**: All services use shared `media` group (GID 1001)
- **Automatic Ownership**: New files inherit correct group via setgid directories
- **Cross-Service Access**: Webshare downloads → Plex indexing → Nextcloud visibility

**Auto-Sync Features:**
- ✅ Libraries sync every 10 minutes automatically
- ✅ Permission fixes every 6 hours via scheduled cleanup
- ✅ New downloads appear across all services
- ✅ Renamed files are detected and updated
- ✅ Automatic metadata fetching and library organization
- ✅ Survives system reboots with cron automation

**🔍 Webshare Search Application

Advanced web interface for webshare.cz API integration with comprehensive real-time features:

**🎯 Core Features:**
- **Search Interface**: Clean, responsive web UI for content discovery
- **Secure Authentication**: Proper salt-based password hashing for webshare.cz API
- **Real-Time Progress**: Live download tracking with actual file system monitoring
- **English Interface**: Fully translated UI (no more Czech "Kontaktuji server")
- **File Permissions**: Automatic UID 1000 mapping for proper Docker volume access
- **Background Downloads**: Non-blocking downloads with progress API endpoints

**🔧 Technical Implementation:**
- **Backend**: Python Flask with webshare.cz XML API integration
- **Real-Time Tracking**: Background download threads with progress monitoring
- **Authentication**: Proper salt/hash mechanism using passlib library
- **Frontend**: Vanilla JavaScript with real-time progress polling
- **Docker Integration**: Runs as containerized service behind nginx proxy

**📊 Progress Tracking Details:**
- Downloads run in background Python threads
- Progress tracked by monitoring actual file size growth
- JavaScript polls `/api/download/progress/<fileId>` every second
- Shows real percentage based on downloaded vs total file size
- Automatic cleanup of completed downloads after 30 seconds
- Error handling for network issues and download failures

**⚙️ Configuration:**
1. Configuration handled automatically via `tools/.env`:
   ```bash
   WEBSHARE_USERNAME=your_username
   WEBSHARE_PASSWORD=your_password
   ```
2. Application auto-authenticates using environment variables
2. Downloads save directly to `$VIDEO_PATH` with correct media group permissions
4. Files automatically appear in Nextcloud and Plex within 10 minutes via scheduled sync

### SSL Certificates

Self-signed certificates are generated automatically. For production use:
1. Obtain certificates from Let's Encrypt or CA
2. Replace files in `nginx/cert/`
3. Update `nginx/conf.d/default.conf` if needed

## 🌐 Network Configuration

### Ports

- **80/443** - Nginx (HTTP/HTTPS reverse proxy)
- **8123** - Home Assistant (direct access, also available via proxy at /)
- **32400** - Plex Media Server (direct access, also available via proxy at /plex/)
- **5000** - Webshare Search (direct access, also available via proxy at /ws/)

### DNS

Add to `/etc/hosts` or configure local DNS:
```
192.168.1.100  ha.local
```

### VPN Access

For VPN access without local DNS, use IP addresses directly:
- **Home Assistant**: https://10.10.20.1/
- **Nextcloud**: https://10.10.20.1/nextcloud/
- **Plex Media Server**: https://10.10.20.1/plex/
- **Webshare Search**: https://10.10.20.1/ws/

## 🔐 Security

- All services run behind SSL-terminated reverse proxy
- Database credentials stored as secret files
- Media servers accessible via direct IP to bypass authentication
- Home Assistant configured with trusted proxy headers

## 📊 Monitoring

### Service Status

```bash
```bash
# Check all services
docker compose -f tools/docker-compose.yml ps

# View service logs
docker compose -f tools/docker-compose.yml logs <service_name>
```

# View cleanup logs
tail -f /var/log/docker-cleanup.log

# Monitor auto-sync activity
tail -f logs/scheduled-sync.log
```

### Health Checks

Access service status pages:
- **Home Assistant**: System → Info
- **Nextcloud**: Settings → Administration → System  
- **Plex Media Server**: https://ha.local/plex/ → Settings → General
- **Webshare**: http://ha.local:5000/health (API endpoint)

### 🔄 Auto-Sync Monitoring

```bash
# Check sync logs
tail -20 logs/scheduled-sync.log

# Verify cron jobs
crontab -l

# Test sync manually
./tools/scheduled-sync.sh

# Check last sync time
ls -la logs/scheduled-sync.log
```

## 🛠️ Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check service logs
docker compose -f tools/docker-compose.yml logs homeassistant

# Restart specific service
docker compose -f tools/docker-compose.yml restart homeassistant
```

**SSL certificate issues:**
```bash
# Regenerate certificates
./tools/create_ssl.sh

# Restart nginx
docker compose -f tools/docker-compose.yml restart nginx
```

**Database connection errors:**
```bash
# Check database logs
docker compose -f tools/docker-compose.yml logs db

# Verify secrets exist
ls -la secrets/
```

**Scheduled sync not working:**
```bash
# Check if cron is running
systemctl status cron

# Test sync manually
./tools/scheduled-sync.sh

# Check for container readiness
docker ps | grep -E "(nextcloud|plex)"

# View sync error logs
tail -20 logs/scheduled-sync.log
```

**Files not appearing in services:**
```bash
# Check storage directory permissions (should use media group)
ls -la $VIDEO_PATH $IMAGE_PATH $DOC_PATH

# Fix permissions automatically (handles all storage directories)
./tools/scheduled-cleanup.sh cleanup

# Check what was fixed
tail -20 logs/scheduled-cleanup.log

# Force service refresh
docker compose -f tools/docker-compose.yml restart app
docker compose -f tools/docker-compose.yml restart plex
```

**Character encoding issues:**
```bash
# Rename folders with Czech characters to English
mv "$MEDIA_PATH/Folder With Čeština" "$MEDIA_PATH/English Folder Name"

# Manually rename episodes or create custom scripts as needed
```

### Reset Services

```bash
# Complete reset (removes all data)
./home_stop.sh
docker system prune -a --volumes
./home_start.sh
```

## 🔄 Backup Strategy

### What to Backup

1. **Configuration files** (tracked in Git):
   - `volumes/homeassistant/config/*.yaml`
   - `nginx/conf.d/default.conf` (auto-generated)
   - `tools/docker-compose.yml`
   - `tools/scheduled-sync.sh`
   - `tools/.env` file (all configuration settings - sensitive data excluded)

2. **Data directories** (backup separately):
   - `volumes/nextcloud/` (user files and database)
   - `volumes/homeassistant/data/` (runtime data)
   - `volumes/plex/` (metadata and configuration)
   - `$VIDEO_PATH` (video library)
   - `$IMAGE_PATH` (photo library)
   - `$DOC_PATH` (document storage)
   - `logs/` (sync and maintenance logs)

3. **System configuration**:
   - Cron jobs: `crontab -l > crontab_backup.txt`
   - Secret files: Document recreation commands

### Git Workflow

```bash
# Commit configuration changes
git add volumes/homeassistant/config/*.yaml
git add tools/docker-compose.yml tools/scheduled-sync.sh tools/scheduled-cleanup.sh
git add tools/generate_nginx_config.sh tools/validate_config.sh
git add home_start.sh home_stop.sh home_update.sh
git add README.md
git commit -m "Update multi-path storage and automation system"
git push

# Note: .env file contains sensitive credentials and should not be committed
# nginx/conf.d/default.conf is auto-generated and doesn't need to be committed
```

### 🔄 Scheduled Sync Backup

```bash
# Backup current cron configuration
crontab -l > crontab_backup.txt

# Restore cron jobs after system migration
crontab crontab_backup.txt

# Verify scheduled sync is working after restore
./tools/scheduled-sync.sh
tail -f logs/scheduled-sync.log
```

### Cron Example: Automated Backups

Use the included helper to install a daily cron job that runs the repository backup.

Install (for the current user):

```bash
# Make the installer executable and run it (no sudo required for user crontab)
chmod +x tools/install_backup_cron.sh
./tools/install_backup_cron.sh

# Verify the installed cron
crontab -l
```

Manual crontab entry (example — runs backup daily at 03:00):

```cron
0 3 * * * /full/path/to/rpi-home-plex/tools/backup_config.sh >> /full/path/to/rpi-home-plex/logs/backup.log 2>&1
```

Notes:
- The installer avoids duplicate entries and preserves existing cron jobs.
- Backups are stored in `home/server_config_backup/` inside the project and rotated (default keep: 14).
- Adjust schedule or retention by editing `tools/install_backup_cron.sh` or setting `KEEP_COUNT` environment variable when running the backup script.


## 🏷️ Version Requirements

- **Docker**: 20.10+
- **Docker Compose**: 3.9+
- **OS**: Ubuntu 20.04+ / Raspberry Pi OS Bullseye+
- **Memory**: 4GB+ recommended
- **Storage**: 32GB+ (more for media files)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Test your changes with `./home_start.sh` (full deployment test)
4. Validate configuration with `./tools/validate_config.sh`
5. Commit changes (`git commit -m 'Add amazing feature'`)
6. Push to branch (`git push origin feature/amazing-feature`)
7. Open merge request

**Development Tips:**
- Configuration is fully automated - no hardcoded values
- All scripts are in `tools/` directory for better organization
- Use `./home_stop.sh` with cleanup options for testing iterations

## 📄 License

This project is open source and available under the MIT License.

## 🆘 Support

For issues and questions:
1. Run `./tools/validate_config.sh` to check configuration
2. Check the troubleshooting section above
3. Review service logs using `docker compose -f tools/docker-compose.yml logs <service_name>`
4. Check deployment status with `docker compose -f tools/docker-compose.yml ps`
5. Create an issue in the GitLab repository

**Quick Diagnostics:**
```bash
# Check all services status
docker compose -f tools/docker-compose.yml ps

# Validate configuration
./tools/validate_config.sh

# Check sync logs
tail -20 logs/scheduled-sync.log

# Test individual components
./tools/create_ssl.sh              # Test SSL generation
./tools/generate_nginx_config.sh   # Test nginx config
./tools/scheduled-sync.sh          # Test sync manually
./tools/fix_homeassistant.sh       # Fix Home Assistant configuration
```

---

**⚡ Built for reliable home server hosting with Docker Swarm**  
**🔧 Zero-configuration deployment with full customization support**