#!/bin/bash
# Queue management utility for BBB MP4 conversions

# Load configuration (same as night-processor.sh)
load_config() {
    local config_file="${BBB_MP4_DIR:-/var/www/bbb-mp4}/config.env"
    
    # Load from config file if exists
    if [ -f "$config_file" ]; then
        source "$config_file"
    fi
    
    # Set defaults if not configured
    export BBB_DOMAIN_NAME="${BBB_DOMAIN_NAME:-bbb.example.com}"
    export COPY_TO_LOCATION="${COPY_TO_LOCATION:-/var/www/bigbluebutton-default/recording}"
    export TIMEZONE="${TIMEZONE:-Asia/Yekaterinburg}"
    export WORK_START_HOUR="${WORK_START_HOUR:-22}"
    export WORK_END_HOUR="${WORK_END_HOUR:-7}"
    export MAX_PARALLEL_JOBS="${MAX_PARALLEL_JOBS:-2}"
    export BBB_MP4_DIR="${BBB_MP4_DIR:-/var/www/bbb-mp4}"
    export QUEUE_DIR="${QUEUE_DIR:-$BBB_MP4_DIR/queue}"
    export LOG_DIR="${LOG_DIR:-$BBB_MP4_DIR/logs}"
    export MP4_OUTPUT_DIR="${MP4_OUTPUT_DIR:-$COPY_TO_LOCATION}"
    export PRESENTATION_DIR="${PRESENTATION_DIR:-/var/bigbluebutton/published/presentation}"
}

# Load configuration
load_config

# Configuration variables
PENDING_QUEUE="$QUEUE_DIR/pending.txt"
PROCESSING_QUEUE="$QUEUE_DIR/processing.txt"
COMPLETED_LOG="$QUEUE_DIR/completed.txt"
FAILED_LOG="$QUEUE_DIR/failed.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage information
usage() {
    echo "BBB MP4 Queue Manager"
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  status                 - Show queue status"
    echo "  list [pending|processing|completed|failed] - List items in queue"
    echo "  add <meeting_id>       - Add meeting to queue"
    echo "  remove <meeting_id>    - Remove meeting from pending queue"
    echo "  clear [pending|failed] - Clear specified queue"
    echo "  retry <meeting_id>     - Move meeting from failed back to pending"
    echo "  retry-all              - Move all failed meetings back to pending"
    echo "  scan                   - Scan for new recordings and add to queue"
    echo "  active                 - Show active conversion containers"
    echo ""
    echo "System Management:"
    echo "  reset                  - Reset all queues and logs (keeps MP4 files)"
    echo "  reset --full           - Full reset including MP4 files deletion"
    echo "  cleanup-mp4            - Remove MP4 files (with backup option)"
    echo "  backup-mp4 <path>      - Backup MP4 files to specified directory"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 add abc123...def456-1234567890123"
    echo "  $0 list pending"
    echo "  $0 retry-all"
}

# Ensure queue files exist
init_queues() {
    mkdir -p "$QUEUE_DIR"
    touch "$PENDING_QUEUE" "$PROCESSING_QUEUE" "$COMPLETED_LOG" "$FAILED_LOG"
}

# Validate meeting ID format
validate_meeting_id() {
    local meeting_id=$1
    if ! echo "$meeting_id" | grep -qE '^[a-f0-9]{40}-[0-9]{13}$'; then
        echo -e "${RED}ERROR: Invalid meeting_id format: $meeting_id${NC}"
        echo "Expected format: 40 hex chars + dash + 13 digits"
        return 1
    fi
    return 0
}

# Show queue status
show_status() {
    echo -e "${BLUE}=== BBB MP4 Queue Status ===${NC}"
    echo ""
    
    local pending_count=$([ -f "$PENDING_QUEUE" ] && wc -l < "$PENDING_QUEUE" || echo 0)
    local processing_count=$([ -f "$PROCESSING_QUEUE" ] && wc -l < "$PROCESSING_QUEUE" || echo 0)
    local completed_count=$([ -f "$COMPLETED_LOG" ] && wc -l < "$COMPLETED_LOG" || echo 0)
    local failed_count=$([ -f "$FAILED_LOG" ] && wc -l < "$FAILED_LOG" || echo 0)
    
    echo -e "${YELLOW}Pending:${NC}    $pending_count recordings"
    echo -e "${BLUE}Processing:${NC} $processing_count recordings"
    echo -e "${GREEN}Completed:${NC}  $completed_count recordings"
    echo -e "${RED}Failed:${NC}     $failed_count recordings"
    echo ""
    
    # Show active containers
    local active_containers=$(docker ps --filter "ancestor=manishkatyan/bbb-mp4" \
                                      --format "{{.Names}}" | \
                                      grep -E '^[a-f0-9]{40}-[0-9]{13}$' | wc -l)
    echo -e "${BLUE}Active conversions:${NC} $active_containers"
    
    # Show working hours status (configurable timezone and hours)
    local hour=$(TZ="$TIMEZONE" date +%H)
    local working_hours_text="${WORK_START_HOUR}:00-$(printf "%02d" $WORK_END_HOUR):00 $TIMEZONE"
    
    # Check if in working hours (handle overnight shifts)
    local in_working_hours=false
    if [ $WORK_START_HOUR -gt $WORK_END_HOUR ]; then
        [ $hour -ge $WORK_START_HOUR ] || [ $hour -lt $WORK_END_HOUR ] && in_working_hours=true
    else
        [ $hour -ge $WORK_START_HOUR ] && [ $hour -lt $WORK_END_HOUR ] && in_working_hours=true
    fi
    
    if [ "$in_working_hours" = true ]; then
        echo -e "${GREEN}Status: Processing hours ($working_hours_text)${NC}"
    else
        echo -e "${YELLOW}Status: Outside processing hours - system paused${NC}"
    fi
}

# List items in specific queue
list_queue() {
    local queue_type=$1
    local file=""
    local title=""
    
    case $queue_type in
        pending)
            file="$PENDING_QUEUE"
            title="Pending Queue"
            ;;
        processing)
            file="$PROCESSING_QUEUE"
            title="Processing Queue"
            ;;
        completed)
            file="$COMPLETED_LOG"
            title="Completed Conversions"
            ;;
        failed)
            file="$FAILED_LOG"
            title="Failed Conversions"
            ;;
        *)
            echo -e "${RED}ERROR: Invalid queue type. Use: pending, processing, completed, failed${NC}"
            return 1
            ;;
    esac
    
    echo -e "${BLUE}=== $title ===${NC}"
    
    if [ -f "$file" ] && [ -s "$file" ]; then
        local count=1
        while IFS= read -r line; do
            echo "$count. $line"
            ((count++))
        done < "$file"
    else
        echo "No items found"
    fi
}

# Add meeting to queue
add_to_queue() {
    local meeting_id=$1
    
    if [ -z "$meeting_id" ]; then
        echo -e "${RED}ERROR: Meeting ID required${NC}"
        return 1
    fi
    
    if ! validate_meeting_id "$meeting_id"; then
        return 1
    fi
    
    # Check if already in any queue
    if grep -q "^$meeting_id$" "$PENDING_QUEUE" "$PROCESSING_QUEUE" "$COMPLETED_LOG" 2>/dev/null; then
        echo -e "${YELLOW}WARNING: Meeting $meeting_id already exists in queues${NC}"
        return 1
    fi
    
    # Check if MP4 already exists
    local mp4_file="/var/www/bigbluebutton-default/recording/${meeting_id}.mp4"
    if [ -f "$mp4_file" ]; then
        echo -e "${YELLOW}WARNING: MP4 already exists for $meeting_id${NC}"
        return 1
    fi
    
    # Add to pending queue
    echo "$meeting_id" >> "$PENDING_QUEUE"
    echo -e "${GREEN}SUCCESS: Added $meeting_id to pending queue${NC}"
}

# Remove meeting from pending queue
remove_from_queue() {
    local meeting_id=$1
    
    if [ -z "$meeting_id" ]; then
        echo -e "${RED}ERROR: Meeting ID required${NC}"
        return 1
    fi
    
    if ! validate_meeting_id "$meeting_id"; then
        return 1
    fi
    
    if grep -q "^$meeting_id$" "$PENDING_QUEUE" 2>/dev/null; then
        sed -i "/^$meeting_id$/d" "$PENDING_QUEUE"
        echo -e "${GREEN}SUCCESS: Removed $meeting_id from pending queue${NC}"
    else
        echo -e "${YELLOW}WARNING: Meeting $meeting_id not found in pending queue${NC}"
    fi
}

# Clear specified queue
clear_queue() {
    local queue_type=$1
    local file=""
    
    case $queue_type in
        pending)
            file="$PENDING_QUEUE"
            ;;
        failed)
            file="$FAILED_LOG"
            ;;
        *)
            echo -e "${RED}ERROR: Can only clear 'pending' or 'failed' queues${NC}"
            return 1
            ;;
    esac
    
    if [ -f "$file" ]; then
        local count=$(wc -l < "$file")
        > "$file"
        echo -e "${GREEN}SUCCESS: Cleared $count items from $queue_type queue${NC}"
    else
        echo -e "${YELLOW}WARNING: $queue_type queue file not found${NC}"
    fi
}

# Retry single failed meeting
retry_meeting() {
    local meeting_id=$1
    
    if [ -z "$meeting_id" ]; then
        echo -e "${RED}ERROR: Meeting ID required${NC}"
        return 1
    fi
    
    if ! validate_meeting_id "$meeting_id"; then
        return 1
    fi
    
    if grep -q "^$meeting_id$" "$FAILED_LOG" 2>/dev/null; then
        # Remove from failed log
        sed -i "/^$meeting_id$/d" "$FAILED_LOG"
        # Add to pending queue (at the beginning for priority)
        if [ -f "$PENDING_QUEUE" ]; then
            echo -e "$meeting_id\n$(cat "$PENDING_QUEUE")" > "$PENDING_QUEUE"
        else
            echo "$meeting_id" > "$PENDING_QUEUE"
        fi
        echo -e "${GREEN}SUCCESS: Moved $meeting_id from failed to pending queue${NC}"
    else
        echo -e "${YELLOW}WARNING: Meeting $meeting_id not found in failed queue${NC}"
    fi
}

# Retry all failed meetings
retry_all_failed() {
    if [ ! -f "$FAILED_LOG" ] || [ ! -s "$FAILED_LOG" ]; then
        echo -e "${YELLOW}WARNING: No failed meetings to retry${NC}"
        return 0
    fi
    
    local count=$(wc -l < "$FAILED_LOG")
    
    # Prepend failed items to pending queue
    if [ -f "$PENDING_QUEUE" ]; then
        cat "$FAILED_LOG" "$PENDING_QUEUE" > "${PENDING_QUEUE}.tmp"
        mv "${PENDING_QUEUE}.tmp" "$PENDING_QUEUE"
    else
        cp "$FAILED_LOG" "$PENDING_QUEUE"
    fi
    
    # Clear failed log
    > "$FAILED_LOG"
    
    echo -e "${GREEN}SUCCESS: Moved $count failed meetings back to pending queue${NC}"
}

# Scan for new recordings
scan_recordings() {
    local presentation_dir="/var/bigbluebutton/published/presentation"
    local mp4_output_dir="/var/www/bigbluebutton-default/recording"
    local added_count=0
    
    echo -e "${BLUE}Scanning for new recordings...${NC}"
    
    if [ ! -d "$presentation_dir" ]; then
        echo -e "${RED}ERROR: Presentation directory not found: $presentation_dir${NC}"
        return 1
    fi
    
    for recording_dir in "$presentation_dir"/*; do
        if [ -d "$recording_dir" ]; then
            local meeting_id=$(basename "$recording_dir")
            
            # Validate meeting ID format
            if ! validate_meeting_id "$meeting_id" 2>/dev/null; then
                continue
            fi
            
            # Check if MP4 already exists
            local mp4_file="$mp4_output_dir/${meeting_id}.mp4"
            if [ -f "$mp4_file" ]; then
                continue
            fi
            
            # Check if already in any queue
            if grep -q "^$meeting_id$" "$PENDING_QUEUE" "$PROCESSING_QUEUE" "$COMPLETED_LOG" 2>/dev/null; then
                continue
            fi
            
            # Add to queue
            echo "$meeting_id" >> "$PENDING_QUEUE"
            echo "Found new recording: $meeting_id"
            ((added_count++))
        fi
    done
    
    echo -e "${GREEN}SUCCESS: Added $added_count new recordings to queue${NC}"
}

# Show active conversion containers
show_active() {
    echo -e "${BLUE}=== Active Conversion Containers ===${NC}"
    
    local containers=$(docker ps --filter "ancestor=manishkatyan/bbb-mp4" \
                              --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}" | \
                              grep -E '^[a-f0-9]{40}-[0-9]{13}')
    
    if [ -n "$containers" ]; then
        echo "MEETING_ID                                      STATUS          RUNNING_FOR"
        echo "$containers"
    else
        echo "No active conversion containers found"
    fi
}

# Main function
main() {
    init_queues
    
    case "$1" in
        status)
            show_status
            ;;
        list)
            list_queue "$2"
            ;;
        add)
            add_to_queue "$2"
            ;;
        remove)
            remove_from_queue "$2"
            ;;
        clear)
            clear_queue "$2"
            ;;
        retry)
            retry_meeting "$2"
            ;;
        retry-all)
            retry_all_failed
            ;;
        scan)
            scan_recordings
            ;;
        active)
            show_active
            ;;
        reset)
            if [ "$2" = "--full" ]; then
                reset_system_full
            else
                reset_system
            fi
            ;;
        cleanup-mp4)
            cleanup_mp4_files
            ;;
        backup-mp4)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Backup path required${NC}"
                echo "Usage: $0 backup-mp4 <backup_directory>"
                exit 1
            fi
            backup_mp4_files "$2"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

# Reset system queues and logs (keep MP4 files)
reset_system() {
    echo -e "${YELLOW}Resetting BBB MP4 Queue System...${NC}"
    
    # Confirm action
    read -p "This will clear all queues and logs. Continue? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Reset cancelled."
        return 1
    fi
    
    # Stop night processor if running
    if pgrep -f "night-processor.sh" > /dev/null; then
        echo -e "${YELLOW}Stopping night processor...${NC}"
        pkill -f "night-processor.sh" || true
        sleep 2
    fi
    
    # Stop any active conversions
    local active_containers=$(docker ps --filter "ancestor=manishkatyan/bbb-mp4" --format "{{.Names}}" | grep -E '^[a-f0-9]{40}-[0-9]{13}$' || true)
    if [ -n "$active_containers" ]; then
        echo -e "${YELLOW}Stopping active conversions...${NC}"
        echo "$active_containers" | while read -r container; do
            echo "Stopping $container"
            docker stop "$container" || true
        done
    fi
    
    # Clear queue files
    echo -e "${BLUE}Clearing queue files...${NC}"
    > "$PENDING_QUEUE"
    > "$PROCESSING_QUEUE"
    > "$COMPLETED_LOG"
    > "$FAILED_LOG"
    
    # Clear logs
    echo -e "${BLUE}Clearing log files...${NC}"
    find "$LOG_DIR" -name "*.log" -type f -exec sh -c '> "$1"' _ {} \;
    
    echo -e "${GREEN}✓ System reset complete${NC}"
    echo -e "${BLUE}MP4 files preserved in: $MP4_OUTPUT_DIR${NC}"
}

# Full reset including MP4 files deletion
reset_system_full() {
    echo -e "${RED}FULL SYSTEM RESET - THIS WILL DELETE ALL MP4 FILES!${NC}"
    
    # Double confirm
    read -p "This will DELETE ALL MP4 files and reset everything. Type 'DELETE' to confirm: " confirm
    if [ "$confirm" != "DELETE" ]; then
        echo "Full reset cancelled."
        return 1
    fi
    
    # First do regular reset
    reset_system
    
    # Delete MP4 files
    echo -e "${RED}Deleting MP4 files...${NC}"
    if [ -d "$MP4_OUTPUT_DIR" ]; then
        local mp4_count=$(find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f | wc -l)
        if [ $mp4_count -gt 0 ]; then
            echo "Found $mp4_count MP4 files to delete"
            find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f -delete
            echo -e "${GREEN}✓ Deleted $mp4_count MP4 files${NC}"
        else
            echo "No MP4 files found"
        fi
    fi
    
    echo -e "${GREEN}✓ Full system reset complete${NC}"
}

# Backup MP4 files to specified directory
backup_mp4_files() {
    local backup_dir="$1"
    
    echo -e "${BLUE}Backing up MP4 files...${NC}"
    
    # Create backup directory
    if ! mkdir -p "$backup_dir"; then
        echo -e "${RED}Error: Cannot create backup directory: $backup_dir${NC}"
        return 1
    fi
    
    # Check if MP4 files exist
    local mp4_count=$(find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f 2>/dev/null | wc -l)
    if [ $mp4_count -eq 0 ]; then
        echo -e "${YELLOW}No MP4 files found to backup${NC}"
        return 0
    fi
    
    # Create timestamped backup subdirectory
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_subdir="$backup_dir/bbb_mp4_backup_$timestamp"
    mkdir -p "$backup_subdir"
    
    echo "Backing up $mp4_count MP4 files to: $backup_subdir"
    
    # Copy files with progress
    local copied=0
    find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f | while read -r file; do
        local filename=$(basename "$file")
        if cp "$file" "$backup_subdir/"; then
            copied=$((copied + 1))
            echo "✓ $filename"
        else
            echo -e "${RED}✗ Failed to copy $filename${NC}"
        fi
    done
    
    # Create manifest file
    echo "# BBB MP4 Backup Manifest" > "$backup_subdir/manifest.txt"
    echo "# Created: $(date)" >> "$backup_subdir/manifest.txt"
    echo "# Source: $MP4_OUTPUT_DIR" >> "$backup_subdir/manifest.txt"
    echo "# Files:" >> "$backup_subdir/manifest.txt"
    find "$backup_subdir" -name "*.mp4" -type f -exec basename {} \; | sort >> "$backup_subdir/manifest.txt"
    
    echo -e "${GREEN}✓ Backup complete: $backup_subdir${NC}"
    echo -e "${BLUE}Files backed up: $(find "$backup_subdir" -name "*.mp4" | wc -l)${NC}"
}

# Clean up MP4 files with options
cleanup_mp4_files() {
    echo -e "${YELLOW}MP4 Files Cleanup${NC}"
    
    # Check if MP4 files exist
    local mp4_count=$(find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f 2>/dev/null | wc -l)
    if [ $mp4_count -eq 0 ]; then
        echo -e "${BLUE}No MP4 files found to clean up${NC}"
        return 0
    fi
    
    echo "Found $mp4_count MP4 files in: $MP4_OUTPUT_DIR"
    echo ""
    echo "Options:"
    echo "1) Delete all MP4 files immediately"
    echo "2) Backup first, then delete"
    echo "3) Show file list only"
    echo "4) Cancel"
    
    read -p "Choose option (1-4): " choice
    
    case $choice in
        1)
            read -p "Delete $mp4_count MP4 files? Type 'DELETE' to confirm: " confirm
            if [ "$confirm" = "DELETE" ]; then
                find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f -delete
                echo -e "${GREEN}✓ Deleted $mp4_count MP4 files${NC}"
            else
                echo "Deletion cancelled"
            fi
            ;;
        2)
            read -p "Enter backup directory path: " backup_path
            if [ -n "$backup_path" ]; then
                if backup_mp4_files "$backup_path"; then
                    read -p "Backup complete. Delete original files? (y/N): " delete_confirm
                    if [[ $delete_confirm =~ ^[Yy]$ ]]; then
                        find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f -delete
                        echo -e "${GREEN}✓ Original files deleted after backup${NC}"
                    fi
                fi
            else
                echo "Backup cancelled - no path provided"
            fi
            ;;
        3)
            echo -e "${BLUE}MP4 Files:${NC}"
            find "$MP4_OUTPUT_DIR" -name "*.mp4" -type f -exec ls -lh {} \; | awk '{print $9 " (" $5 ")"}'
            ;;
        4)
            echo "Cleanup cancelled"
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

# Run main function with all arguments
main "$@"

