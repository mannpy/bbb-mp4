#!/bin/bash
# Installation script for BBB MP4 Night Queue System
# This script sets up the delayed conversion system

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BBB_MP4_DIR="/var/www/bbb-mp4"
POST_PUBLISH_DIR="/usr/local/bigbluebutton/core/scripts/post_publish"
QUEUE_DIR="$BBB_MP4_DIR/queue"
LOG_DIR="$BBB_MP4_DIR/logs"

# Logging function
log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if BBB is installed
check_bbb_installation() {
    if [ ! -d "/var/bigbluebutton" ]; then
        log_error "BigBlueButton installation not found"
        exit 1
    fi
    
    if [ ! -d "$POST_PUBLISH_DIR" ]; then
        log_error "BigBlueButton post_publish directory not found"
        exit 1
    fi
    
    log_success "BigBlueButton installation found"
}

# Check if original bbb-mp4 is installed
check_original_bbb_mp4() {
    if [ ! -d "$BBB_MP4_DIR" ]; then
        log_error "Original bbb-mp4 installation not found at $BBB_MP4_DIR"
        log_error "Please install the original bbb-mp4 first"
        exit 1
    fi
    
    if [ ! -f "$BBB_MP4_DIR/bbb-mp4.sh" ]; then
        log_error "bbb-mp4.sh not found. Original installation incomplete"
        exit 1
    fi
    
    log_success "Original bbb-mp4 installation found"
}

# Backup original files
backup_original_files() {
    log_message "Creating backups of original files..."
    
    # Backup original post_publish script if it exists
    if [ -f "$POST_PUBLISH_DIR/bbb_mp4.rb" ]; then
        cp "$POST_PUBLISH_DIR/bbb_mp4.rb" "$POST_PUBLISH_DIR/bbb_mp4.rb.backup.$(date +%Y%m%d_%H%M%S)"
        log_success "Backed up original bbb_mp4.rb"
    fi
}

# Create directories
create_directories() {
    log_message "Creating queue and log directories..."
    
    mkdir -p "$QUEUE_DIR"
    mkdir -p "$LOG_DIR"
    
    # Create empty queue files
    touch "$QUEUE_DIR/pending.txt"
    touch "$QUEUE_DIR/processing.txt"
    touch "$QUEUE_DIR/completed.txt"
    touch "$QUEUE_DIR/failed.txt"
    
    log_success "Created queue and log directories"
}

# Set permissions
set_permissions() {
    log_message "Setting proper permissions..."
    
    # Make scripts executable
    chmod +x "$BBB_MP4_DIR/night-processor.sh"
    chmod +x "$BBB_MP4_DIR/stop-night-processor.sh"
    chmod +x "$BBB_MP4_DIR/queue-manager.sh"
    chmod +x "$BBB_MP4_DIR/bbb_mp4_queue.rb"
    
    # Set ownership to bigbluebutton user
    chown -R bigbluebutton:bigbluebutton "$BBB_MP4_DIR"
    
    log_success "Set permissions and ownership"
}

# Install new post_publish script
install_post_publish_script() {
    log_message "Installing new post_publish script..."
    
    cp "$BBB_MP4_DIR/bbb_mp4_queue.rb" "$POST_PUBLISH_DIR/bbb_mp4.rb"
    chown bigbluebutton:bigbluebutton "$POST_PUBLISH_DIR/bbb_mp4.rb"
    chmod +x "$POST_PUBLISH_DIR/bbb_mp4.rb"
    
    log_success "Installed new post_publish script"
}

# Setup cron jobs
setup_cron_jobs() {
    log_message "Setting up cron jobs for bigbluebutton user..."
    
    # Create temporary cron file
    local temp_cron="/tmp/bbb_mp4_cron"
    
    # Get existing crontab for bigbluebutton user (if any)
    sudo -u bigbluebutton crontab -l > "$temp_cron" 2>/dev/null || true
    
    # Remove any existing bbb-mp4 night processor entries
    sed -i '/night-processor.sh/d' "$temp_cron"
    sed -i '/stop-night-processor.sh/d' "$temp_cron"
    
    # Add new cron entries (UTC times for Yekaterinburg 22:00-07:00)
    echo "# BBB MP4 Night Queue System (UTC times: 17:00-02:00 = Yekaterinburg 22:00-07:00)" >> "$temp_cron"
    echo "0 17 * * * $BBB_MP4_DIR/night-processor.sh >> $LOG_DIR/cron.log 2>&1" >> "$temp_cron"
    echo "15 2 * * * $BBB_MP4_DIR/stop-night-processor.sh >> $LOG_DIR/cron.log 2>&1" >> "$temp_cron"
    echo "" >> "$temp_cron"
    
    # Install new crontab
    sudo -u bigbluebutton crontab "$temp_cron"
    rm -f "$temp_cron"
    
    log_success "Configured cron jobs"
    log_message "  - Night processor starts at 22:00 Yekaterinburg (17:00 UTC) daily"
    log_message "  - Night processor auto-stops at 07:00 Yekaterinburg (02:00 UTC)"
    log_message "  - Force-stop backup runs at 07:15 Yekaterinburg (02:15 UTC) if needed"
}

# Scan existing recordings and add to queue
scan_existing_recordings() {
    log_message "Scanning for existing recordings to add to queue..."
    
    sudo -u bigbluebutton "$BBB_MP4_DIR/queue-manager.sh" scan
    
    log_success "Completed scanning existing recordings"
}

# Create systemd service (optional)
create_systemd_service() {
    log_message "Creating systemd service for manual control..."
    
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
    
    log_success "Created systemd service: bbb-mp4-night-processor"
    log_message "  You can manually start/stop with:"
    log_message "  systemctl start bbb-mp4-night-processor"
    log_message "  systemctl stop bbb-mp4-night-processor"
}

# Show final instructions
show_final_instructions() {
    echo ""
    echo -e "${GREEN}=== Installation Complete! ===${NC}"
    echo ""
    echo "The BBB MP4 Night Queue System has been successfully installed."
    echo ""
    echo -e "${YELLOW}What changed:${NC}"
    echo "  • Post-publish script now adds recordings to queue instead of immediate conversion"
    echo "  • Night processor runs from 22:00 to 07:00 Yekaterinburg time daily"
    echo "  • Maximum 2 parallel conversions to limit CPU usage"
    echo "  • Queue management system with retry capabilities"
    echo ""
    echo -e "${YELLOW}Management commands:${NC}"
    echo "  • Check status:           $BBB_MP4_DIR/queue-manager.sh status"
    echo "  • List pending:           $BBB_MP4_DIR/queue-manager.sh list pending"
    echo "  • Add recording:          $BBB_MP4_DIR/queue-manager.sh add <meeting-id>"
    echo "  • Scan for new:           $BBB_MP4_DIR/queue-manager.sh scan"
    echo "  • Retry failed:           $BBB_MP4_DIR/queue-manager.sh retry-all"
    echo ""
    echo -e "${YELLOW}Manual control:${NC}"
    echo "  • Start night processor:  systemctl start bbb-mp4-night-processor"
    echo "  • Force run during day:   $BBB_MP4_DIR/night-processor.sh --force"
    echo "  • Stop night processor:   systemctl stop bbb-mp4-night-processor"
    echo "  • View logs:              tail -f $LOG_DIR/night-processor.log"
    echo ""
    echo -e "${YELLOW}Directories:${NC}"
    echo "  • Queue files:            $QUEUE_DIR/"
    echo "  • Log files:              $LOG_DIR/"
    echo "  • MP4 output:             /var/www/bigbluebutton-default/recording/"
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "  1. Test the system: $BBB_MP4_DIR/queue-manager.sh status"
    echo "  2. Wait for tonight (22:00 Yekaterinburg) or manually start for testing"
    echo "  3. Monitor logs: tail -f $LOG_DIR/night-processor.log"
    echo ""
}

# Main installation function
main() {
    echo -e "${BLUE}=== BBB MP4 Night Queue System Installation ===${NC}"
    echo ""
    
    check_root
    check_bbb_installation
    check_original_bbb_mp4
    
    backup_original_files
    create_directories
    set_permissions
    install_post_publish_script
    setup_cron_jobs
    scan_existing_recordings
    create_systemd_service
    
    show_final_instructions
}

# Run installation
main "$@"

