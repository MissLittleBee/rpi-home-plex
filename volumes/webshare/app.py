#!/usr/bin/env python3
from flask import Flask, render_template, request, jsonify, send_from_directory
import os
import threading
import time
import json
import requests
from webshare_api import WebshareAPI
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret-key')

# Initialize Webshare API client
webshare_client = WebshareAPI()

# Track active downloads
active_downloads = {}

# Get credentials and download path from environment variables
WEBSHARE_USERNAME = os.environ.get('WEBSHARE_USERNAME')
WEBSHARE_PASSWORD = os.environ.get('WEBSHARE_PASSWORD')
DOWNLOAD_PATH = os.environ.get('DOWNLOAD_PATH', '/downloads')
MOVIES_PATH = os.environ.get('MOVIES_PATH', '/downloads/movies')
SERIES_PATH = os.environ.get('SERIES_PATH', '/downloads/series')

# Plex configuration for triggering library refresh
PLEX_URL = os.environ.get('PLEX_URL', 'http://plex:32400')
PLEX_TOKEN = os.environ.get('PLEX_TOKEN', '')

# Auto-login on startup if credentials are provided
login_status = "not_configured"
login_message = "No credentials configured"

if WEBSHARE_USERNAME and WEBSHARE_PASSWORD:
    try:
        webshare_client.login(WEBSHARE_USERNAME, WEBSHARE_PASSWORD)
        login_status = "success"
        login_message = f"Successfully logged in as {WEBSHARE_USERNAME}"
        logger.info("Successfully auto-logged in to Webshare.cz")
    except Exception as e:
        login_status = "error"
        login_message = f"Login failed: {str(e)}"
        logger.error(f"Auto-login failed: {str(e)}")
else:
    login_status = "not_configured"
    login_message = "Webshare.cz credentials not configured"

@app.route('/')
def index():
    """Main page with search form"""
    return render_template('index.html')

@app.route('/api/login', methods=['POST'])
def login():
    """Check login status or re-login if needed"""
    try:
        if webshare_client.logged_in:
            return jsonify({'success': True, 'message': 'Already logged in'})
        
        # Try to re-login with environment credentials
        if WEBSHARE_USERNAME and WEBSHARE_PASSWORD:
            result = webshare_client.login(WEBSHARE_USERNAME, WEBSHARE_PASSWORD)
            return jsonify({'success': True, 'message': 'Logged in successfully'})
        else:
            return jsonify({'success': False, 'error': 'No credentials configured'}), 400
    
    except Exception as e:
        logger.error(f'Login error: {str(e)}')
        return jsonify({'success': False, 'error': str(e)}), 400

@app.route('/api/status')
def status():
    """Get login status"""
    return jsonify({
        'logged_in': webshare_client.logged_in,
        'credentials_configured': bool(WEBSHARE_USERNAME and WEBSHARE_PASSWORD),
        'login_status': login_status,
        'login_message': login_message,
        'username': WEBSHARE_USERNAME if WEBSHARE_USERNAME else None
    })

@app.route('/api/search', methods=['POST'])
def search():
    """Search for files on webshare.cz"""
    try:
        data = request.get_json()
        query = data.get('query')
        
        if not query:
            return jsonify({'success': False, 'error': 'Query parameter is required'}), 400
        
        results = webshare_client.search(query)
        return jsonify({'success': True, 'results': results})
    
    except Exception as e:
        logger.error(f'Search error: {str(e)}')
        return jsonify({'success': False, 'error': str(e)}), 500

def download_file_background(file_id, file_name, download_path):
    """Background download function"""
    try:
        # Update status to downloading
        active_downloads[file_id] = {
            'status': 'downloading',
            'fileName': file_name,
            'progress': 0,
            'message': 'Starting download...',
            'startTime': time.time()
        }
        
        # Get download info first
        download_info = webshare_client.initiate_download(file_id)
        download_url = download_info['downloadUrl']
        expected_size = download_info.get('fileSize', 0)
        
        if not file_name:
            file_name = download_info['fileName']
        
        # Ensure download directory exists
        os.makedirs(download_path, exist_ok=True)
        
        # Full file path
        file_path = os.path.join(download_path, file_name)
        
        # Update status
        active_downloads[file_id]['message'] = 'Connecting to server...'
        active_downloads[file_id]['progress'] = 5
        
        # Download the file with progress tracking
        logger.info(f'Starting download of {file_name}...')
        
        response = webshare_client.session.get(download_url, stream=True)
        response.raise_for_status()
        
        total_size = int(response.headers.get('content-length', expected_size or 0))
        downloaded_size = 0
        
        active_downloads[file_id]['message'] = f'Downloading... 0%'
        active_downloads[file_id]['progress'] = 10
        active_downloads[file_id]['totalSize'] = total_size
        
        with open(file_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
                    downloaded_size += len(chunk)
                    
                    # Update progress
                    if total_size > 0:
                        progress = min(90, 10 + int((downloaded_size / total_size) * 80))
                        active_downloads[file_id]['progress'] = progress
                        active_downloads[file_id]['message'] = f'Downloading... {progress-10}%'
                        active_downloads[file_id]['downloadedSize'] = downloaded_size
        
        # Set proper file permissions (readable by group and others)
        try:
            os.chmod(file_path, 0o644)
            logger.info(f'Set file permissions to 644 for {file_name}')
        except Exception as e:
            logger.warning(f'Could not set file permissions for {file_name}: {str(e)}')
        
        # Final status update
        active_downloads[file_id]['status'] = 'completed'
        active_downloads[file_id]['progress'] = 100
        active_downloads[file_id]['message'] = 'Download completed!'
        active_downloads[file_id]['filePath'] = file_path
        active_downloads[file_id]['finalSize'] = downloaded_size
        
        logger.info(f'Download completed: {file_name} ({webshare_client._format_file_size(downloaded_size)})')
        
        # Trigger Plex library refresh after successful download
        if PLEX_TOKEN:
            try:
                refresh_url = f'{PLEX_URL}/library/sections/all/refresh?X-Plex-Token={PLEX_TOKEN}'
                response = requests.put(refresh_url, timeout=5)
                if response.status_code == 200:
                    logger.info('Successfully triggered Plex library refresh')
                else:
                    logger.warning(f'Plex API returned status code: {response.status_code}')
            except Exception as e:
                logger.error(f'Error triggering Plex library refresh: {str(e)}')
        else:
            logger.warning('PLEX_TOKEN not configured, skipping library refresh')
        
        # Remove from active downloads after 30 seconds
        def cleanup():
            time.sleep(30)
            if file_id in active_downloads:
                del active_downloads[file_id]
        
        threading.Thread(target=cleanup, daemon=True).start()
        
    except Exception as e:
        logger.error(f'Background download failed: {str(e)}')
        active_downloads[file_id] = {
            'status': 'error',
            'fileName': file_name,
            'progress': 0,
            'message': f'Download failed: {str(e)}',
            'error': str(e)
        }

@app.route('/api/download', methods=['POST'])
def download():
    """Initiate download from webshare.cz"""
    try:
        data = request.get_json()
        file_id = data.get('fileId')
        file_name = data.get('fileName')
        content_type = data.get('contentType', 'movie')  # 'movie' or 'series'
        
        if not file_id:
            return jsonify({'success': False, 'error': 'File ID is required'}), 400
        
        # Determine download path based on content type
        if content_type == 'series':
            download_path = SERIES_PATH
        else:
            download_path = MOVIES_PATH
        
        logger.info(f'Downloading {file_name} as {content_type} to {download_path}')
        
        # Check if already downloading
        if file_id in active_downloads:
            return jsonify({
                'success': True, 
                'message': f'Download already in progress: {file_name}',
                'status': active_downloads[file_id]['status'],
                'progress': active_downloads[file_id]['progress']
            })
        
        # Start background download with correct path
        download_thread = threading.Thread(
            target=download_file_background,
            args=(file_id, file_name, download_path),
            daemon=True
        )
        download_thread.start()
        
        return jsonify({
            'success': True, 
            'message': f'Download started: {file_name}',
            'fileId': file_id
        })
    
    except Exception as e:
        logger.error(f'Download error: {str(e)}')
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/download/progress/<file_id>')
def download_progress(file_id):
    """Get download progress for a specific file"""
    try:
        if file_id in active_downloads:
            return jsonify({
                'success': True,
                'download': active_downloads[file_id]
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Download not found or completed'
            }), 404
    
    except Exception as e:
        logger.error(f'Progress check error: {str(e)}')
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/downloads')
def list_downloads():
    """List downloaded files from both movies and series directories"""
    try:
        files = []
        
        # List movies
        if os.path.exists(MOVIES_PATH):
            for filename in os.listdir(MOVIES_PATH):
                filepath = os.path.join(MOVIES_PATH, filename)
                if os.path.isfile(filepath):
                    stat = os.stat(filepath)
                    files.append({
                        'name': filename,
                        'size': stat.st_size,
                        'sizeFormatted': webshare_client._format_file_size(stat.st_size),
                        'modified': stat.st_mtime,
                        'type': 'movie',
                        'typeLabel': '🎬 Movie'
                    })
        
        # List series
        if os.path.exists(SERIES_PATH):
            for filename in os.listdir(SERIES_PATH):
                filepath = os.path.join(SERIES_PATH, filename)
                if os.path.isfile(filepath):
                    stat = os.stat(filepath)
                    files.append({
                        'name': filename,
                        'size': stat.st_size,
                        'sizeFormatted': webshare_client._format_file_size(stat.st_size),
                        'modified': stat.st_mtime,
                        'type': 'series',
                        'typeLabel': '📺 Series'
                    })
        
        # Sort by modification time (newest first)
        files.sort(key=lambda x: x['modified'], reverse=True)
        
        return jsonify({'success': True, 'files': files})
    
    except Exception as e:
        logger.error(f'List downloads error: {str(e)}')
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'OK', 'service': 'webshare-search-app'})

@app.route('/static/<path:filename>')
def static_files(filename):
    """Serve static files"""
    return send_from_directory('static', filename)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('DEBUG', 'False').lower() == 'true'
    
    logger.info(f'Starting Webshare Search App on port {port}')
    app.run(host='0.0.0.0', port=port, debug=debug)