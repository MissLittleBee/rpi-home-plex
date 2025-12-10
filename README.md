# 🏠 RPi Home Server Stack

Complete Docker-based home server with media streaming, file sharing, home automation, and secure remote access via Cloudflare tunnel.

## 📋 Overview

**Fully automated deployment** - Run `./home_start.sh` and answer prompts to deploy everything.

**🎯 Key Features:**
- **🚀 One-Command Setup** - Interactive configuration and deployment
- **📁 Organized Storage** - Movies/Series auto-routing for downloads
- **👥 Shared Permissions** - Media group (GID 1001) for cross-service access
- **🔄 Auto-Maintenance** - Sync every 10min, cleanup every 6h, backups daily at 2 AM
- **🛡️ Cloud Security** - Cloudflare Zero Trust tunnel for secure remote access
- **📱 Mobile Ready** - Optimized for mobile apps and smart TVs

**📦 Services:**
- **Nginx** - SSL reverse proxy
- **Nextcloud** - File sharing and collaboration
- **Home Assistant** - Home automation platform
- **Plex Media Server** - Media streaming with hardware transcoding
- **Webshare Search** - Download manager with content type selector
- **Cloudflare Tunnel** - Secure remote access without port forwarding
- **MariaDB** - Database backend

## 🏗️ Architecture

```
Internet → Cloudflare Tunnel → Nginx (SSL) → Services
                                  ├── Home Assistant (/)
                                  ├── Nextcloud (/nextcloud)
                                  ├── Plex (/plex)
                                  └── Webshare (/ws)
                                  
Host Storage → Docker Volumes → Services
├── /mnt/data/together/movies/
│   ├── movies/    → Plex Movies + Webshare downloads
│   └── series/  → Plex Series + Webshare downloads
```

## 🚀 Quick Start

### Prerequisites

- Ubuntu/Debian-based Linux (tested on Raspberry Pi OS)
- Docker and Docker Compose installed
- Domain name (for Cloudflare tunnel)

### Deploy

```bash
# Clone repository
git clone <repo-url>
cd rpi-home-plex

# Deploy everything (interactive setup)
./home_start.sh
```

The script will:
1. ✅ Check prerequisites (Docker, OpenSSL, curl, cron)
2. ✅ Prompt for configuration (hostname, IPs, credentials, paths)
3. ✅ Generate `.env` file and SSL certificates
4. ✅ Create docker-compose.yml
5. ✅ Set up directories with correct permissions
6. ✅ Deploy all containers
7. ✅ Configure cron jobs for automation
8. ✅ Run initial library sync

### Configuration Prompts

You'll be asked for:
- **Hostname/Domain** (e.g., `rpi.local`)
- **Server IP** (auto-detected)
- **VPN IP** (optional)
- **Webshare.cz credentials** (username/password)
- **Plex Claim Token** (optional, from https://www.plex.tv/claim/)
- **Cloudflare Tunnel Token** (from Cloudflare Zero Trust dashboard)
- **Storage Paths**:
  - Base video path (default: `/mnt/data/together/movies`)
  - Movies subdirectory (default: `movies`)
  - Series subdirectory (default: `series`)
- **Nextcloud Admin** (default: `admin`)
- **Timezone** (auto-detected)

### Access Services

**Local Access (via nginx reverse proxy):**
- Home Assistant: `https://rpi.local/`
- Nextcloud: `https://rpi.local/nextcloud/`
- Plex: `https://rpi.local/plex/`
- Webshare: `https://rpi.local/ws/`

**Direct Device Access (for apps/TVs):**
- Plex: `http://192.168.1.x:32400`

**Remote Access (via Cloudflare):**
- Home Assistant: `https://ha.yourdomain.com`
- Nextcloud: `https://nextcloud.yourdomain.com`
- Plex: `https://plex.yourdomain.com`

## 📁 Project Structure

```
rpi-home-plex/
├── home_start.sh              # 🚀 Main deployment script
├── home_stop.sh               # ⏹️ Stop services with cleanup options
├── home_update.sh             # 🔄 Update and redeploy
├── tools/
│   ├── .env                   # ⚙️ Configuration (auto-generated)
│   ├── docker-compose.yml     # Service definitions
│   ├── Dockerfile.webshare    # Webshare app build
│   ├── scheduled-sync.sh      # Library sync (every 10min)
│   ├── scheduled-cleanup.sh   # Maintenance (every 6h)
│   ├── scheduled-backup.sh    # Config backup (daily 2 AM)
│   ├── create_ssl.sh          # SSL certificate generator
│   ├── generate_nginx_config.sh # Nginx config generator
│   └── validate_config.sh     # Configuration validator
├── nginx/
│   ├── conf.d/
│   │   └── default.conf       # Reverse proxy config (auto-generated)
│   └── cert/                  # SSL certificates (auto-generated)
├── secrets/
│   ├── db_password            # MariaDB password (auto-generated)
│   └── db_root_password       # MariaDB root password (auto-generated)
├── volumes/
│   ├── homeassistant/         # HA config and data
│   ├── nextcloud/             # Nextcloud data
│   ├── plex/                  # Plex metadata
│   └── webshare/              # Webshare app
├── logs/                      # Application logs
└── README.md
```

## 🔧 Management

### Stack Control

```bash
# Start (uses existing config if available)
./home_start.sh

# Reconfigure without stopping
./home_start.sh --reconfigure

# Stop with cleanup options
./home_stop.sh

# Update containers
./home_update.sh
```

### Manual Operations

```bash
# Trigger sync immediately
./tools/scheduled-sync.sh

# Run maintenance (permissions + Docker cleanup)
./tools/scheduled-cleanup.sh cleanup

# Backup configs
./tools/scheduled-backup.sh

# Validate configuration
./tools/validate_config.sh
```

### View Logs

```bash
# Container logs
docker compose -f tools/docker-compose.yml logs <service>

# Sync logs
tail -f logs/scheduled-sync.log

# Cleanup logs
tail -f logs/scheduled-cleanup.log

# Backup logs
tail -f logs/scheduled-backup.log
```

### Service Status

```bash
# Check all containers
docker compose -f tools/docker-compose.yml ps

# Check cron jobs
crontab -l
```

## ⚙️ Configuration

All configuration stored in `tools/.env` (auto-generated during setup):

```bash
# Network
HOSTNAME=rpi.local
SERVER_IP=192.168.1.100
VPN_IP=10.10.20.1

# Webshare.cz
WEBSHARE_USERNAME=username
WEBSHARE_PASSWORD=password

# Plex (auto-removed after first start for security)
PLEX_CLAIM_TOKEN=claim-xxxx

# Cloudflare
TUNNEL_TOKEN=your-tunnel-token

# Storage
VIDEO_PATH=/mnt/data/together/movies
MOVIES_PATH=/mnt/data/together/movies/movies
SERIES_PATH=/mnt/data/together/movies/series

# Nextcloud
NEXTCLOUD_USER=admin
NEXTCLOUD_PASSWORD=auto-generated

# System
TIMEZONE=Europe/Prague
```

### Reconfiguration

```bash
# Reconfigure everything
./home_start.sh --reconfigure

# Or stop and remove config
./home_stop.sh  # Choose "Y" to remove config
./home_start.sh
```

## 🎬 Plex Configuration

### Critical: Container Paths

**⚠️ IMPORTANT**: Plex requires **container paths**, not host paths!

**Container Path Mapping:**
```
Host Path                              → Container Path
/mnt/data/together/movies/movies        → /media/videos/movies
/mnt/data/together/movies/series      → /media/videos/series
```

**✅ Correct Library Setup:**
1. Access Plex: `https://rpi.local/plex/` or `http://192.168.1.x:32400/web`
2. Settings → Manage → Libraries → Add Library
3. For Movies: Select `/media/videos/movies` (container path)
4. For Series: Select `/media/videos/series` (container path)

**❌ Wrong:** `/mnt/data/together/movies/movies` (host path)  
**✅ Right:** `/media/videos/series` (container path)

### Dual Access Mode

- **Reverse Proxy** (`https://rpi.local/plex/`): Browser access with local network detection
- **Direct Access** (`http://192.168.1.x:32400`): Mobile apps, smart TVs, auto-discovery

### Auto-Sync

- New files detected every 10 minutes via `scheduled-sync.sh`
- Uses Plex API for efficient section-by-section scanning
- Permissions fixed automatically every 6 hours

### Fixing Wrong Paths

If libraries are empty:

```bash
# Verify container can see files
docker exec rpi_home_plex ls -la /media/videos/movies
docker exec rpi_home_plex ls -la /media/videos/series

# Fix via Plex web UI
# Settings → Libraries → Edit → Remove wrong path → Add correct container path
```

## 🔍 Webshare Integration

**Features:**
- English web interface for webshare.cz
- Content type selector (🎬 Movies / 📺 Series)
- Real-time download progress tracking
- Automatic routing to correct directories
- Proper file permissions for Plex access

**How It Works:**
1. Search for content at `https://rpi.local/ws/`
2. Select Movie or Series
3. Click download
4. Files save to `MOVIES_PATH` or `SERIES_PATH`
5. Plex detects files within 10 minutes via auto-sync

## ☁️ Nextcloud Setup

**First-Time Setup** (manual via web interface):

1. Access: `https://rpi.local/nextcloud/`
2. Create admin account (use your preferred credentials)
3. Database configuration:
   - Database & user: `nextcloud`
   - Password: Check `secrets/db_password`
   - Host: `db`
4. Click "Finish setup"

**Pre-configured:**
- ✅ Database connection (MariaDB)
- ✅ Trusted domains
- ✅ Storage mounts
- ✅ Reverse proxy headers
- ✅ SSL termination

**To Reset:**
```bash
./home_stop.sh
sudo rm -rf volumes/nextcloud/
./home_start.sh
```

## 🛡️ Cloudflare Tunnel

**Setup:**
1. Create tunnel in Cloudflare Zero Trust dashboard
2. Get tunnel token
3. Add token during `./home_start.sh` setup
4. Configure public hostnames:
   - `ha.yourdomain.com` → `https://nginx`
   - `nextcloud.yourdomain.com` → `https://nginx/nextcloud`
   - `plex.yourdomain.com` → `https://nginx/plex`

**Benefits:**
- No port forwarding required
- DDoS protection
- Access logging
- Zero Trust security policies

## 🔄 Automated Maintenance

### Scheduled Sync (Every 10 Minutes)

- Scans Plex libraries via API
- Detects new/changed files
- Updates metadata automatically
- Logs all activity to `logs/scheduled-sync.log`

### Cleanup (Every 6 Hours)

- Fixes file permissions (UID 1000, GID 1001, 775)
- Removes unused Docker containers
- Prunes dangling images
- Cleans build cache
- Logs to `logs/scheduled-cleanup.log`

### Backups (Daily at 2 AM)

- Home Assistant configs (YAML, custom components)
- Nextcloud configs (PHP files)
- Nginx configs
- Docker configs (.env, compose files, scripts)
- Keeps last 7 days
- Logs to `logs/scheduled-backup.log`

**Cron Jobs** (installed automatically):
```cron
*/10 * * * * /path/to/scheduled-sync.sh
0 */6 * * * /path/to/scheduled-cleanup.sh cleanup
0 2 * * * /path/to/scheduled-backup.sh
@reboot /path/to/scheduled-sync.sh
```

## 🛠️ Troubleshooting

### Services Not Starting

```bash
# Check logs
docker compose -f tools/docker-compose.yml logs <service>

# Restart specific service
docker compose -f tools/docker-compose.yml restart <service>
```

### Plex Library Empty

```bash
# Verify container paths (not host paths)
docker exec rpi_home_plex ls -la /media/videos/movies

# Check permissions
ls -la /mnt/data/together/movies/

# Fix permissions
./tools/scheduled-cleanup.sh cleanup

# Manual sync
./tools/scheduled-sync.sh
```

### Files Not Appearing

```bash
# Check permissions
ls -la $MOVIES_PATH $SERIES_PATH

# Fix automatically
./tools/scheduled-cleanup.sh cleanup

# Force refresh
docker compose -f tools/docker-compose.yml restart plex
./tools/scheduled-sync.sh
```

### Sync Not Working

```bash
# Check cron
systemctl status cron
crontab -l

# Test manually
./tools/scheduled-sync.sh

# View logs
tail -20 logs/scheduled-sync.log
```

### SSL Issues

```bash
# Regenerate certificates
./tools/create_ssl.sh

# Restart nginx
docker compose -f tools/docker-compose.yml restart nginx
```

### Complete Reset

```bash
./home_stop.sh
docker system prune -a --volumes
sudo rm -rf volumes/ secrets/ nginx/conf.d/ nginx/cert/
./home_start.sh
```

## 💾 Backup Strategy

### What's Backed Up Automatically

Daily at 2 AM via `scheduled-backup.sh`:
- ✅ Home Assistant configs
- ✅ Nextcloud configs
- ✅ Nginx configs
- ✅ Docker configs (.env, compose, scripts)
- ✅ Network configs
- ✅ Auto-cleanup (keeps 7 days)

Saved to: `backup/` (excluded from git)

### Manual Backup

```bash
# Run now
./tools/scheduled-backup.sh

# View backups
ls -lh backup/

# Check logs
tail -f logs/scheduled-backup.log
```

### Additional Data (Manual Backup Needed)

**User Data:**
- `volumes/nextcloud/` - User files and database
- `volumes/homeassistant/data/` - Runtime data
- `volumes/plex/` - Metadata and settings
- `$MOVIES_PATH` and `$SERIES_PATH` - Media files

**System:**
- `crontab -l > crontab_backup.txt`
- `secrets/db_password` and `secrets/db_root_password`

## 🔐 Security & Privacy

### Git Protection

`.gitignore` excludes all sensitive data:
- `volumes/` - All container data
- `logs/` - Application logs
- `secrets/` - Database passwords
- `nginx/cert/` - SSL certificates
- `tools/.env*` - Configuration files
- `backup/` - Config backups

**Safe to commit:**
- Scripts (`*.sh`)
- Documentation (`README.md`)
- Dockerfiles
- Base configurations

### Removing Sensitive Data from History

If you accidentally committed sensitive files:

```bash
# Install git-filter-repo
sudo apt install git-filter-repo

# Remove sensitive path
git filter-repo --path volumes/homeassistant/config/ --invert-paths

# Force push
git push --force --all
```

## 📊 System Requirements

- **Docker**: 20.10+
- **Docker Compose**: 3.9+
- **OS**: Ubuntu 20.04+ / Raspberry Pi OS Bullseye+
- **Memory**: 4GB+ recommended (8GB+ for transcoding)
- **Storage**: 32GB+ for system, separate storage for media

## 🆘 Support

**Diagnostics:**
```bash
# Check all services
docker compose -f tools/docker-compose.yml ps

# Validate config
./tools/validate_config.sh

# Check logs
tail -20 logs/scheduled-sync.log
tail -20 logs/scheduled-cleanup.log

# Test components
./tools/scheduled-sync.sh
./tools/scheduled-cleanup.sh cleanup
```

**Common Commands:**
```bash
# Restart everything
./home_stop.sh && ./home_start.sh

# Reconfigure
./home_start.sh --reconfigure

# Check cron
crontab -l

# View all logs
docker compose -f tools/docker-compose.yml logs -f
```

## 🤝 Contributing

1. Fork repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Test with `./home_start.sh`
4. Validate with `./tools/validate_config.sh`
5. Commit: `git commit -m 'Add amazing feature'`
6. Push: `git push origin feature/amazing-feature`
7. Create pull request

## 📄 License

MIT License - See LICENSE file for details

---

**🚀 One command to deploy, zero configuration needed**
