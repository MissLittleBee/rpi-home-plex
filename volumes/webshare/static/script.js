// Global variables
let isLoggedIn = false;

// Utility functions
function showElement(elementId) {
    document.getElementById(elementId).style.display = 'block';
}

function hideElement(elementId) {
    document.getElementById(elementId).style.display = 'none';
}

function showStatus(elementId, message, type = 'info') {
    const statusElement = document.getElementById(elementId);
    statusElement.textContent = message;
    statusElement.className = `status-message ${type}`;
    statusElement.style.display = 'block';

    // Auto-hide success messages after 5 seconds
    if (type === 'success') {
        setTimeout(() => {
            if (statusElement.textContent === message) {
                clearStatus(elementId);
            }
        }, 5000);
    }
}

// Toast notification function for immediate feedback
function showToast(message, type = 'info', duration = 3000) {
    // Create toast element
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    toast.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        padding: 12px 20px;
        border-radius: 6px;
        color: white;
        font-weight: 500;
        z-index: 1000;
        opacity: 0;
        transform: translateX(100%);
        transition: all 0.3s ease;
        max-width: 300px;
        word-wrap: break-word;
    `;

    // Set background color based on type
    switch (type) {
        case 'success': toast.style.backgroundColor = '#28a745'; break;
        case 'error': toast.style.backgroundColor = '#dc3545'; break;
        case 'warning': toast.style.backgroundColor = '#ffc107'; toast.style.color = '#212529'; break;
        default: toast.style.backgroundColor = '#007bff'; break;
    }

    document.body.appendChild(toast);

    // Show toast
    setTimeout(() => {
        toast.style.opacity = '1';
        toast.style.transform = 'translateX(0)';
    }, 100);

    // Hide toast after duration
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(100%)';
        setTimeout(() => {
            document.body.removeChild(toast);
        }, 300);
    }, duration);
}

function clearStatus(elementId) {
    const statusElement = document.getElementById(elementId);
    statusElement.style.display = 'none';
    statusElement.textContent = '';
}

// Check connection status on load
async function checkStatus() {
    try {
        console.log('Checking status...');
        const response = await makeRequest('/api/status');
        console.log('Status response:', response);

        if (response.logged_in) {
            isLoggedIn = true;
            const message = response.username ?
                `✅ Logged in as ${response.username}` :
                '✅ Successfully connected to Webshare.cz';
            showStatus('connectionStatus', message, 'success');
        } else if (response.credentials_configured) {
            // Show detailed error message to user
            let errorMessage = '❌ Failed to connect to Webshare.cz';

            if (response.login_message) {
                // Extract useful information from the login message
                if (response.login_message.includes('Network error')) {
                    errorMessage = '❌ Network error - cannot connect to Webshare.cz. Check internet connection.';
                } else if (response.login_message.includes('Login failed')) {
                    errorMessage = '❌ Invalid credentials. Check username and password.';
                } else {
                    errorMessage = `❌ Login error: ${response.login_message}`;
                }
            }

            showStatus('connectionStatus', errorMessage, 'error');

            // Add retry button
            const statusElement = document.getElementById('connectionStatus');
            statusElement.innerHTML = errorMessage +
                '<br><button onclick="retryConnection()" style="margin-top: 10px; padding: 5px 10px; background: #007bff; color: white; border: none; border-radius: 4px; cursor: pointer;">🔄 Try Again</button>';
        } else {
            showStatus('connectionStatus', '❌ Credentials not configured. Check environment variables.', 'error');
        }

        // Show detailed login information if available
        if (response.login_message) {
            const statusElement = document.getElementById('connectionStatus');
            const currentMessage = statusElement.textContent;
            statusElement.innerHTML = `${currentMessage}<br><small>${response.login_message}</small>`;
        }

        // Load downloaded files
        await refreshDownloads();
    } catch (error) {
        console.error('Status check error:', error);
        showStatus('connectionStatus', `❌ Connection error: ${error.message}`, 'error');
        showToast('Failed to verify connection status', 'error');
    }
}

// Refresh downloads list
async function refreshDownloads() {
    try {
        const response = await makeRequest('/api/downloads');

        if (response.success) {
            displayDownloads(response.files);
        }
    } catch (error) {
        document.getElementById('downloadsContainer').innerHTML =
            `<p class="error">Error loading downloads: ${error.message}</p>`;
    }
}

// Display downloaded files
function displayDownloads(files) {
    const container = document.getElementById('downloadsContainer');

    if (!files || files.length === 0) {
        container.innerHTML = '<p class="no-downloads">No downloaded files found.</p>';
        return;
    }

    container.innerHTML = files.map(file => `
        <div class="download-item">
            <div class="download-header">
                <div class="download-name" title="${escapeHtml(file.name)}">
                    📁 ${escapeHtml(file.name)}
                </div>
                <div class="download-info">
                    ${file.typeLabel ? `<span class="type-badge">${escapeHtml(file.typeLabel)}</span>` : ''}
                    <div class="download-size">${escapeHtml(file.sizeFormatted)}</div>
                </div>
            </div>
            <div class="download-date">
                Downloaded: ${new Date(file.modified * 1000).toLocaleString()}
            </div>
        </div>
    `).join('');
}

function showLoading() {
    showElement('loadingSpinner');
}

function hideLoading() {
    hideElement('loadingSpinner');
}

function setButtonLoading(buttonId, loading = true) {
    const button = document.getElementById(buttonId);
    if (!button) {
        console.error('Button not found:', buttonId);
        return;
    }

    if (loading) {
        if (!button.dataset.originalText) {
            button.dataset.originalText = button.textContent;
        }
        button.disabled = true;
        button.textContent = 'Loading...';
    } else {
        button.disabled = false;
        button.textContent = button.dataset.originalText || 'Search';
    }
}

// API functions
async function makeRequest(url, options = {}) {
    try {
        // Add path prefix if we're being served through nginx proxy
        const basePath = window.location.pathname.startsWith('/ws') ? '/ws' : '';
        const fullUrl = basePath + url;

        console.log('Making request to:', fullUrl);

        const response = await fetch(fullUrl, {
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            ...options
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.error || `HTTP error! status: ${response.status}`);
        }

        return data;
    } catch (error) {
        console.error('API request failed:', error);
        throw error;
    }
}

// Retry connection function
async function retryConnection() {
    showStatus('connectionStatus', '🔄 Attempting to reconnect...', 'info');
    await checkStatus();
}

// Search function
async function search() {
    const query = document.getElementById('searchQuery').value.trim();

    // Show immediate feedback that button was clicked
    showToast('🔍 Starting search...', 'info', 1500);

    if (!query) {
        showStatus('searchStatus', '⚠️ Please enter a search term', 'error');
        showToast('⚠️ Please enter a search term', 'warning');
        // Flash the input field to draw attention
        const searchInput = document.getElementById('searchQuery');
        searchInput.style.borderColor = '#dc3545';
        setTimeout(() => {
            searchInput.style.borderColor = '';
        }, 2000);
        return;
    }

    if (!isLoggedIn) {
        showStatus('searchStatus', '❌ Not connected to Webshare.cz. Check connection status above.', 'error');
        showToast('❌ Not connected to Webshare.cz', 'error');
        return;
    }

    console.log('Starting search for:', query);
    clearStatus('searchStatus');
    setButtonLoading('searchBtn');
    hideElement('resultsSection');
    showLoading();

    try {
        showStatus('searchStatus', 'Searching...', 'info');

        const response = await makeRequest('/api/search', {
            method: 'POST',
            body: JSON.stringify({ query })
        });

        console.log('Search response:', response);

        if (response.success) {
            displayResults(response.results);
            showStatus('searchStatus', `Found ${response.results.length} results`, 'success');
            showToast(`✅ Found ${response.results.length} results for "${query}"`, 'success');
        } else {
            showStatus('searchStatus', `Search failed: ${response.error || 'Unknown error'}`, 'error');
            showToast('❌ Search failed', 'error');
        }
    } catch (error) {
        console.error('Search error:', error);
        showStatus('searchStatus', `Search error: ${error.message}`, 'error');
        showToast('❌ Search error', 'error');
    } finally {
        setButtonLoading('searchBtn', false);
        document.getElementById('searchBtn').textContent = 'Search';
        hideLoading();
    }
}

// Display search results
function displayResults(results) {
    const resultsContainer = document.getElementById('resultsContainer');

    if (!results || results.length === 0) {
        resultsContainer.innerHTML = `
            <div class="no-results">
                <h3>No Results</h3>
                <p>Try a different search term or check for typos.</p>
            </div>
        `;
        showElement('resultsSection');
        return;
    }

    console.log('Displaying results:', results);

    resultsContainer.innerHTML = results.map(result => `
        <div class="result-item fade-in-up">
            <div class="result-header">
                <div class="result-name" title="${escapeHtml(result.name || '')}">
                    ${escapeHtml(result.name || 'Unknown file')}
                </div>
                <div class="result-size">${escapeHtml(result.sizeFormatted || 'N/A')}</div>
            </div>
            <div class="result-details">
                <div class="result-detail">
                    <span>📁 Type:</span>
                    <span>${escapeHtml(result.type || 'unknown')}</span>
                </div>
                <div class="result-detail">
                    <span>⬇️ Downloads:</span>
                    <span>${result.downloads || 0}</span>
                </div>
                <div class="result-detail">
                    <span>⭐ Rating:</span>
                    <span>${result.rating || 0}/5</span>
                </div>
                ${result.date ? `
                    <div class="result-detail">
                        <span>📅 Date:</span>
                        <span>${escapeHtml(result.date)}</span>
                    </div>
                ` : ''}
            </div>
            <button class="download-btn" onclick="initiateDownload('${escapeHtml(result.id || '')}', '${escapeHtml(result.name || '')}')">
                Download
            </button>
            <div class="download-progress" id="progress-${escapeHtml(result.id || '')}">
                <div class="progress-bar">
                    <div class="progress-fill"></div>
                    <div class="progress-text">0%</div>
                </div>
            </div>
        </div>
    `).join('');

    showElement('resultsSection');
}

// Download function
async function initiateDownload(fileId, fileName) {
    if (!isLoggedIn) {
        showToast('❌ Not connected to Webshare.cz', 'error');
        return;
    }

    const button = event.target;
    const originalText = button.textContent;
    const progressContainer = document.getElementById(`progress-${fileId}`);
    const progressFill = progressContainer ? progressContainer.querySelector('.progress-fill') : null;
    const progressText = progressContainer ? progressContainer.querySelector('.progress-text') : null;

    // Get selected content type
    const contentTypeRadio = document.querySelector('input[name="contentType"]:checked');
    const contentType = contentTypeRadio ? contentTypeRadio.value : 'movie';

    // Disable button and show initial state
    button.disabled = true;
    button.textContent = 'Starting download...';

    // Show progress bar
    if (progressContainer) {
        progressContainer.style.display = 'block';
        updateProgress(progressFill, progressText, 0, 'Preparing download...');
    }

    try {
        const typeLabel = contentType === 'series' ? '📺 Series' : '🎬 Movie';
        showToast(`🔄 Starting ${typeLabel} download...`, 'info');

        const response = await makeRequest('/api/download', {
            method: 'POST',
            body: JSON.stringify({ fileId, fileName, contentType })
        });

        if (response.success) {
            // Start real progress tracking
            await trackDownloadProgress(fileId, progressFill, progressText, button, originalText, fileName);
        }
    } catch (error) {
        console.error('Download error:', error);

        // Determine error message based on error content
        let errorMsg = error.message;
        let userMsg = 'Download error';

        if (error.message.includes('temporarily unavailable')) {
            errorMsg = 'File is temporarily unavailable on webshare.cz server';
            userMsg = '⚠️ File temporarily unavailable - try later or different file';
        } else if (error.message.includes('Network error')) {
            errorMsg = 'Network error when connecting to webshare.cz';
            userMsg = '🌐 Connection problem - check internet connection';
        } else if (error.message.includes('Login')) {
            errorMsg = 'Problem with webshare.cz login';
            userMsg = '🔑 Login error - check credentials';
        }

        // Error state
        if (progressContainer) {
            progressFill.style.background = 'linear-gradient(90deg, #dc3545, #c82333)';
            updateProgress(progressFill, progressText, 0, 'Failed!');

            setTimeout(() => {
                progressContainer.style.display = 'none';
                progressFill.style.background = 'linear-gradient(90deg, #28a745, #20c997)';
            }, 3000);
        }

        showStatus('searchStatus', `❌ ${errorMsg}`, 'error');
        showToast(userMsg, 'error', 5000);

        button.textContent = originalText;
        button.disabled = false;
    }
}

// Real progress tracking function
async function trackDownloadProgress(fileId, progressFill, progressText, button, originalText, fileName) {
    const progressContainer = progressFill ? progressFill.parentElement.parentElement : null;
    let checkCount = 0;
    const maxChecks = 300; // 5 minutes maximum (300 * 1000ms)

    const checkProgress = async () => {
        try {
            const response = await makeRequest(`/api/download/progress/${fileId}`);

            if (response.success) {
                const download = response.download;

                // Update progress bar
                updateProgress(progressFill, progressText, download.progress, download.message);

                if (download.status === 'completed') {
                    // Success state
                    button.textContent = 'Downloaded!';
                    button.style.background = 'linear-gradient(135deg, #48bb78, #38a169)';

                    showStatus('searchStatus', '✅ File downloaded successfully!', 'success');
                    showToast(`✅ File ${fileName} downloaded successfully`, 'success', 5000);

                    // Refresh downloads list
                    setTimeout(() => {
                        refreshDownloads();
                    }, 1000);

                    // Reset button after delay
                    setTimeout(() => {
                        button.textContent = originalText;
                        button.disabled = false;
                        button.style.background = '';
                        if (progressContainer) {
                            progressContainer.style.display = 'none';
                        }
                    }, 3000);

                    return; // Stop checking

                } else if (download.status === 'error') {
                    // Error state
                    if (progressFill) {
                        progressFill.style.background = 'linear-gradient(90deg, #dc3545, #c82333)';
                        updateProgress(progressFill, progressText, 0, 'Download failed!');
                    }

                    showStatus('searchStatus', `❌ Download failed: ${download.error || 'Unknown error'}`, 'error');
                    showToast('❌ Download failed', 'error', 5000);

                    setTimeout(() => {
                        if (progressContainer) {
                            progressContainer.style.display = 'none';
                        }
                        if (progressFill) {
                            progressFill.style.background = 'linear-gradient(90deg, #28a745, #20c997)';
                        }
                    }, 3000);

                    button.textContent = originalText;
                    button.disabled = false;
                    return; // Stop checking

                } else {
                    // Still downloading, check again in 1 second
                    checkCount++;
                    if (checkCount < maxChecks) {
                        setTimeout(checkProgress, 1000);
                    } else {
                        // Timeout
                        updateProgress(progressFill, progressText, 0, 'Timeout - check downloads list');
                        showToast('⏱️ Download tracking timeout - check downloads list', 'warning', 5000);
                        button.textContent = originalText;
                        button.disabled = false;
                    }
                }
            } else {
                // Download not found or completed - check downloads list
                await refreshDownloads();
                updateProgress(progressFill, progressText, 100, 'Completed');

                button.textContent = 'Downloaded!';
                button.style.background = 'linear-gradient(135deg, #48bb78, #38a169)';

                setTimeout(() => {
                    button.textContent = originalText;
                    button.disabled = false;
                    button.style.background = '';
                    if (progressContainer) {
                        progressContainer.style.display = 'none';
                    }
                }, 3000);
            }

        } catch (error) {
            console.error('Progress check error:', error);
            // Continue checking - might be temporary network issue
            checkCount++;
            if (checkCount < maxChecks) {
                setTimeout(checkProgress, 2000); // Wait longer on error
            } else {
                updateProgress(progressFill, progressText, 0, 'Error tracking progress');
                button.textContent = originalText;
                button.disabled = false;
            }
        }
    };

    // Start checking immediately
    checkProgress();
}

// Helper function to update progress bar
function updateProgress(progressFill, progressText, percentage, text = null) {
    if (progressFill) {
        progressFill.style.width = `${percentage}%`;
    }
    if (progressText) {
        progressText.textContent = text || `${percentage}%`;
    }
}



// Utility function to escape HTML
function escapeHtml(text) {
    const map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, function (m) { return map[m]; });
}

// Event listeners
document.addEventListener('DOMContentLoaded', function () {
    console.log('DOM loaded, JavaScript is working!');
    console.log('Current URL:', window.location.href);
    console.log('Current pathname:', window.location.pathname);

    // Check status on load
    checkStatus();

    // Enter key support for search
    document.getElementById('searchQuery').addEventListener('keypress', function (e) {
        if (e.key === 'Enter') {
            search();
        }
    });

    // Store original button text
    document.getElementById('searchBtn').dataset.originalText = 'Search';

    // Focus on search input
    document.getElementById('searchQuery').focus();

    console.log('Event listeners set up');
});