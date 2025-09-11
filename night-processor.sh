#!/bin/bash
# Night processor for BBB MP4 conversions
# Runs from 22:00 to 07:00 Yekaterinburg time (17:00-02:00 UTC), processes queue with max 2 parallel jobs

# Configuration
MAX_PARALLEL_JOBS=2
QUEUE_DIR="/var/www/bbb-mp4/queue"
PENDING_QUEUE="$QUEUE_DIR/pending.txt"
PROCESSING_QUEUE="$QUEUE_DIR/processing.txt"
COMPLETED_LOG="$QUEUE_DIR/completed.txt"
FAILED_LOG="$QUEUE_DIR/failed.txt"
LOG_FILE="/var/www/bbb-mp4/logs/night-processor.log"
MP4_OUTPUT_DIR="/var/www/bigbluebutton-default/recording"
PRESENTATION_DIR="/var/bigbluebutton/published/presentation"

# Ensure directories exist
mkdir -p "$QUEUE_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$PENDING_QUEUE" "$PROCESSING_QUEUE" "$COMPLETED_LOG" "$FAILED_LOG"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if we're in working hours (22:00-07:00 Yekaterinburg time)
# Server runs on UTC, convert to Asia/Yekaterinburg timezone (UTC+5)
is_working_hours() {
    local hour=$(TZ='Asia/Yekaterinburg' date +%H)
    [ $hour -ge 22 ] || [ $hour -lt 7 ]
}

# Count active BBB-MP4 conversion containers
count_active_conversions() {
    docker ps --filter "ancestor=manishkatyan/bbb-mp4" \
              --format "{{.Names}}" | \
              grep -E '^[a-f0-9]{40}-[0-9]{13}$' | \
              wc -l
}

# Get list of active conversion containers
get_active_conversion_containers() {
    docker ps --filter "ancestor=manishkatyan/bbb-mp4" \
              --format "{{.Names}}" | \
              grep -E '^[a-f0-9]{40}-[0-9]{13}$'
}

# Check if specific conversion is running
is_conversion_running() {
    local meeting_id=$1
    docker ps --filter "ancestor=manishkatyan/bbb-mp4" \
              --filter "name=^${meeting_id}$" \
              --format "{{.Names}}" | \
              grep -q "^${meeting_id}$"
}

# Validate meeting ID format
validate_meeting_id() {
    local meeting_id=$1
    echo "$meeting_id" | grep -qE '^[a-f0-9]{40}-[0-9]{13}$'
}

# Check if recording exists and MP4 doesn't exist
should_convert() {
    local meeting_id=$1
    local recording_path="$PRESENTATION_DIR/$meeting_id"
    local mp4_path="$MP4_OUTPUT_DIR/${meeting_id}.mp4"
    
    # Check if recording exists
    if [ ! -d "$recording_path" ]; then
        log_message "WARNING: Recording not found for $meeting_id at $recording_path"
        return 1
    fi
    
    # Check if MP4 already exists
    if [ -f "$mp4_path" ]; then
        log_message "INFO: MP4 already exists for $meeting_id, skipping"
        return 1
    fi
    
    return 0
}

# Start conversion for one meeting
start_conversion() {
    local meeting_id=$1
    
    # Validate meeting ID format
    if ! validate_meeting_id "$meeting_id"; then
        log_message "ERROR: Invalid meeting_id format: $meeting_id"
        echo "$meeting_id" >> "$FAILED_LOG"
        return 1
    fi
    
    # Check if should convert
    if ! should_convert "$meeting_id"; then
        echo "$meeting_id" >> "$COMPLETED_LOG"
        return 1
    fi
    
    log_message "INFO: Starting conversion for $meeting_id"
    
    # Add to processing queue
    echo "$meeting_id" >> "$PROCESSING_QUEUE"
    
    # Start conversion script
    /var/www/bbb-mp4/bbb-mp4.sh "$meeting_id"
    
    # Monitor completion in background
    {
        local start_time=$(date +%s)
        local timeout=7200  # 2 hours timeout
        
        # Wait for container to start (give it 60 seconds)
        sleep 60
        
        # Wait for conversion to complete or timeout
        while is_conversion_running "$meeting_id"; do
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            
            if [ $elapsed -gt $timeout ]; then
                log_message "ERROR: Conversion timeout for $meeting_id after $elapsed seconds"
                docker stop "$meeting_id" 2>/dev/null || true
                echo "$meeting_id" >> "$FAILED_LOG"
                sed -i "/^${meeting_id}$/d" "$PROCESSING_QUEUE"
                exit 1
            fi
            
            sleep 30
        done
        
        # Remove from processing queue
        sed -i "/^${meeting_id}$/d" "$PROCESSING_QUEUE"
        
        # Check if conversion was successful
        local mp4_path="$MP4_OUTPUT_DIR/${meeting_id}.mp4"
        if [ -f "$mp4_path" ] && [ -s "$mp4_path" ]; then
            log_message "SUCCESS: Conversion completed for $meeting_id"
            echo "$meeting_id" >> "$COMPLETED_LOG"
        else
            log_message "ERROR: Conversion failed for $meeting_id - no MP4 file created"
            echo "$meeting_id" >> "$FAILED_LOG"
        fi
        
    } &
}

# Clean up old entries from processing queue (in case of script crashes)
cleanup_processing_queue() {
    if [ -f "$PROCESSING_QUEUE" ]; then
        while IFS= read -r meeting_id; do
            if [ -n "$meeting_id" ] && ! is_conversion_running "$meeting_id"; then
                log_message "CLEANUP: Removing stale entry from processing queue: $meeting_id"
                sed -i "/^${meeting_id}$/d" "$PROCESSING_QUEUE"
            fi
        done < "$PROCESSING_QUEUE"
    fi
}

# Main processing loop
main() {
    log_message "INFO: Starting night processor"
    log_message "INFO: Max parallel jobs: $MAX_PARALLEL_JOBS"
    log_message "INFO: Will only manage containers with image: manishkatyan/bbb-mp4"
    
    # Check for force flag
    local force_run=false
    if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        force_run=true
        log_message "INFO: Force mode enabled - will run regardless of time"
    fi
    
    # Cleanup any stale processing entries
    cleanup_processing_queue
    
    # Main processing loop - run if working hours OR force mode
    while is_working_hours || [ "$force_run" = true ]; do
        # If force mode and outside working hours, log it
        if [ "$force_run" = true ] && ! is_working_hours; then
            log_message "INFO: Running in force mode outside working hours"
        fi
        # Check if queue has items
        if [ ! -s "$PENDING_QUEUE" ]; then
            if [ "$force_run" = true ]; then
                log_message "INFO: Queue is empty in force mode - exiting"
                break
            else
                log_message "INFO: Queue is empty, waiting..."
                sleep 300  # Wait 5 minutes before checking again
                continue
            fi
        fi
        
        # Check current load
        local active_jobs=$(count_active_conversions)
        
        if [ $active_jobs -lt $MAX_PARALLEL_JOBS ]; then
            # Get next job from queue
            local meeting_id=$(head -n1 "$PENDING_QUEUE" 2>/dev/null)
            
            if [ -n "$meeting_id" ]; then
                # Remove from pending queue
                sed -i '1d' "$PENDING_QUEUE"
                
                # Start conversion
                if start_conversion "$meeting_id"; then
                    log_message "INFO: Started job $meeting_id. Active conversions: $((active_jobs + 1))"
                fi
            fi
        else
            log_message "INFO: Max parallel jobs reached ($active_jobs). Waiting..."
            local active_containers=$(get_active_conversion_containers | tr '\n' ' ')
            log_message "INFO: Active containers: $active_containers"
        fi
        
        # Wait before next iteration
        sleep 60
    done
    
    # Outside working hours - wait for active jobs to complete
    log_message "INFO: Outside working hours. Waiting for active jobs to complete..."
    
    while [ $(count_active_conversions) -gt 0 ]; do
        local active=$(count_active_conversions)
        local active_containers=$(get_active_conversion_containers | tr '\n' ' ')
        log_message "INFO: Waiting for $active active conversions to complete: $active_containers"
        sleep 60
    done
    
    log_message "INFO: Night processor finished"
}

# Handle signals for graceful shutdown
graceful_shutdown() {
    log_message "INFO: Received shutdown signal - starting graceful shutdown"
    log_message "INFO: Waiting for active conversions to complete..."
    
    # Wait for active jobs to complete (same logic as end of working hours)
    while [ $(count_active_conversions) -gt 0 ]; do
        local active=$(count_active_conversions)
        local active_containers=$(get_active_conversion_containers | tr '\n' ' ')
        log_message "INFO: Waiting for $active active conversions to complete: $active_containers"
        sleep 30  # Shorter sleep when shutting down
    done
    
    log_message "INFO: Graceful shutdown completed"
    exit 0
}

trap 'graceful_shutdown' TERM INT

# Run main function with arguments
main "$@"

