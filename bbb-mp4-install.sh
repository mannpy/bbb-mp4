#!/bin/bash
# BBB MP4 Installation Script with Night Queue System
# This script installs the complete BBB MP4 system with configurable night processing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (use sudo)"
        exit 1
    fi
}

# Detect BBB domain and setup configuration
setup_config() {
    log_message "Setting up configuration..."
    
    # Copy example config if doesn't exist
    if [ ! -f "config.env" ]; then
        cp config.env.example config.env
        log_success "Created config.env from example"
    fi
    
    # Auto-detect BBB domain
    local bbb_domain=$(bbb-conf --secret | grep URL | cut -d'/' -f3 2>/dev/null || echo "")
    if [ -n "$bbb_domain" ]; then
        sed -i "s/BBB_DOMAIN_NAME=.*/BBB_DOMAIN_NAME=$bbb_domain/g" config.env
        log_success "Auto-detected BBB domain: $bbb_domain"
    fi
    
    # Load configuration
    set -a
    source config.env
    set +a
    
    # Ensure COPY_TO_LOCATION and MP4_OUTPUT_DIR are the same
    export MP4_OUTPUT_DIR="$COPY_TO_LOCATION"
}

# Install Docker if not present
install_docker() {
    if ! command -v docker &> /dev/null; then
        log_message "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        rm get-docker.sh
        log_success "Docker installed successfully"
    else
        log_success "Docker is already installed"
    fi
}

# Make scripts executable
setup_permissions() {
    log_message "Setting up file permissions..."
    chmod +x *.sh
    chown -R bigbluebutton:bigbluebutton .
    log_success "File permissions configured"
}

# Install post-publish script
install_post_publish() {
    log_message "Installing post-publish script..."
    
    # Backup original if exists
    if [ -f "/usr/local/bigbluebutton/core/scripts/post_publish/bbb_mp4.rb" ]; then
        cp /usr/local/bigbluebutton/core/scripts/post_publish/bbb_mp4.rb \
           /usr/local/bigbluebutton/core/scripts/post_publish/bbb_mp4.rb.backup
        log_success "Backed up original post-publish script"
    fi
    
    # Install new queue-based post-publish script
    cp bbb_mp4_queue.rb /usr/local/bigbluebutton/core/scripts/post_publish/bbb_mp4.rb
    chmod +x /usr/local/bigbluebutton/core/scripts/post_publish/bbb_mp4.rb
    
    log_success "Installed queue-based post-publish script"
}

# Update BigBlueButton playback interface
update_playback_interface() {
    log_message "Updating BigBlueButton playback interface..."
    
    local index_path="/var/bigbluebutton/playback/presentation/2.3/index.html"
    local index_backup="/var/bigbluebutton/playbook/presentation/2.3/index_default.html"
    
    if [ ! -f "$index_backup" ]; then
        # Create backup of original
        cp "$index_path" "$index_backup" 2>/dev/null || true
        
        # Copy download button script
        cp download-button.js /var/bigbluebutton/playback/presentation/2.3/
        
        # Add download button to interface
        sed -i 's/<\/body>/<script src="\/playback\/presentation\/2.3\/download-button.js"><\/script><\/body>/g' "$index_path"
        
        log_success "Updated playback interface with download button"
    else
        log_success "Playback interface already updated"
    fi
}

# Setup night queue system
setup_night_queue() {
    log_message "Setting up night queue system..."
    
    # Create directories
    mkdir -p "$QUEUE_DIR" "$LOG_DIR"
    touch "$QUEUE_DIR"/{pending.txt,processing.txt,completed.txt,failed.txt}
    
    # Setup cron jobs
    local temp_cron="/tmp/bbb_mp4_cron"
    sudo -u bigbluebutton crontab -l > "$temp_cron" 2>/dev/null || true
    
    # Remove existing entries
    sed -i '/night-processor.sh/d' "$temp_cron"
    sed -i '/stop-night-processor.sh/d' "$temp_cron"
    
    # Calculate UTC times from configured timezone and hours
    local start_utc=$(TZ="$TIMEZONE" date -d "today $WORK_START_HOUR:00" -u '+%H')
    local stop_utc=$(TZ="$TIMEZONE" date -d "today $WORK_END_HOUR:00" -u '+%H')
    local backup_stop_utc=$(TZ="$TIMEZONE" date -d "today $WORK_END_HOUR:$BACKUP_STOP_DELAY" -u '+%H %M')
    
    # Add new cron entries
    echo "# BBB MP4 Night Queue System" >> "$temp_cron"
    echo "# Working hours: $WORK_START_HOUR:00-$WORK_END_HOUR:00 $TIMEZONE" >> "$temp_cron"
    echo "0 $start_utc * * * $BBB_MP4_DIR/night-processor.sh >> $LOG_DIR/cron.log 2>&1" >> "$temp_cron"
    echo "$backup_stop_utc * * * $BBB_MP4_DIR/stop-night-processor.sh >> $LOG_DIR/cron.log 2>&1" >> "$temp_cron"
    echo "" >> "$temp_cron"
    
    # Install crontab
    sudo -u bigbluebutton crontab "$temp_cron"
    rm -f "$temp_cron"
    
    log_success "Configured night queue cron jobs"
}

# Create systemd service
create_systemd_service() {
    log_message "Creating systemd service..."
    
    cat > /etc/systemd/system/bbb-mp4-night-processor.service << EOF
[Unit]
Description=BigBlueButton MP4 Night Processor
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=bigbluebutton
Group=bigbluebutton
ExecStart=$BBB_MP4_DIR/night-processor.sh
ExecStop=$BBB_MP4_DIR/stop-night-processor.sh
Restart=no
StandardOutput=append:$LOG_DIR/systemd.log
StandardError=append:$LOG_DIR/systemd.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log_success "Created systemd service"
}

# Scan existing recordings
scan_existing_recordings() {
    log_message "Scanning for existing recordings..."
    sudo -u bigbluebutton "$BBB_MP4_DIR/queue-manager.sh" scan
    log_success "Completed scanning existing recordings"
}

# Show final instructions
show_final_instructions() {
    echo ""
    echo -e "${GREEN}=== BBB MP4 Installation Complete! ===${NC}"
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo "  • Timezone: $TIMEZONE"
    echo "  • Working hours: $WORK_START_HOUR:00-$WORK_END_HOUR:00"
    echo "  • Max parallel jobs: $MAX_PARALLEL_JOBS"
    echo "  • Queue directory: $QUEUE_DIR"
    echo "  • Log directory: $LOG_DIR"
    echo ""
    echo -e "${YELLOW}Queue Management:${NC}"
    echo "  • Check status:     ./queue-manager.sh status"
    echo "  • List pending:     ./queue-manager.sh list pending"
    echo "  • Add recording:    ./queue-manager.sh add <meeting-id>"
    echo "  • Scan for new:     ./queue-manager.sh scan"
    echo ""
    echo -e "${YELLOW}Manual Control:${NC}"
    echo "  • Normal start:     systemctl start bbb-mp4-night-processor"
    echo "  • Force run now:    ./night-processor.sh --force"
    echo "  • Stop processing:  systemctl stop bbb-mp4-night-processor"
    echo "  • View logs:        tail -f $LOG_DIR/night-processor.log"
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo "  • Edit settings:    nano config.env"
    echo "  • Restart cron:     sudo -u bigbluebutton crontab -l"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "  1. Test the system: ./queue-manager.sh status"
    echo "  2. Wait for tonight or test with: ./night-processor.sh --force"
    echo "  3. Monitor logs: tail -f $LOG_DIR/night-processor.log"
}

# Main installation function
main() {
    echo -e "${GREEN}BBB MP4 Night Queue System Installer${NC}"
    echo "========================================"
    
    check_root
    setup_config
    install_docker
    setup_permissions
    install_post_publish
    update_playback_interface
    setup_night_queue
    create_systemd_service
    scan_existing_recordings
    show_final_instructions
    
    echo ""
    echo -e "${GREEN}Installation completed successfully!${NC}"
}

# Run main installation
main "$@"