#!/bin/bash
# Queue management utility for BBB MP4 conversions

QUEUE_DIR="/var/www/bbb-mp4/queue"
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
    
    # Show working hours status (Yekaterinburg time)
    local hour=$(TZ='Asia/Yekaterinburg' date +%H)
    if [ $hour -ge 22 ] || [ $hour -lt 7 ]; then
        echo -e "${GREEN}Status: Night processing hours (22:00-07:00 Yekaterinburg)${NC}"
    else
        echo -e "${YELLOW}Status: Day time - processing paused${NC}"
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
        *)
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"

