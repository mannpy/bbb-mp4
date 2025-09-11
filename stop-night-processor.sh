#!/bin/bash
# Stop night processor and active BBB-MP4 conversions

# Load configuration (same as night-processor.sh)
load_config() {
    local config_file="${BBB_MP4_DIR:-/var/www/bbb-mp4}/config.env"
    
    # Load from config file if exists
    if [ -f "$config_file" ]; then
        source "$config_file"
    fi
    
    # Set defaults if not configured
    export BBB_MP4_DIR="${BBB_MP4_DIR:-/var/www/bbb-mp4}"
    export QUEUE_DIR="${QUEUE_DIR:-$BBB_MP4_DIR/queue}"
    export LOG_DIR="${LOG_DIR:-$BBB_MP4_DIR/logs}"
}

# Load configuration
load_config

# Configuration variables
LOG_FILE="$LOG_DIR/night-processor.log"
PROCESSING_QUEUE="$QUEUE_DIR/processing.txt"
FAILED_LOG="$QUEUE_DIR/failed.txt"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get list of active BBB-MP4 conversion containers
get_active_conversion_containers() {
    docker ps --filter "ancestor=manishkatyan/bbb-mp4" \
              --format "{{.Names}}" | \
              grep -E '^[a-f0-9]{40}-[0-9]{13}$'
}

# Main stop function
main() {
    log_message "INFO: Starting morning shutdown check (backup safety stop)"
    
    # Check if night-processor is still running
    local processor_pids=$(pgrep -f "night-processor.sh")
    if [ -n "$processor_pids" ]; then
        log_message "WARNING: Night processor still running after 15 minutes grace period"
        log_message "INFO: Stopping night-processor processes: $processor_pids"
        
        # Send graceful termination signal first
        pkill -TERM -f "night-processor.sh"
        sleep 10
        
        # Check if still running
        if pgrep -f "night-processor.sh" > /dev/null; then
            log_message "WARNING: Night processor not responding to TERM, sending KILL"
            pkill -9 -f "night-processor.sh"
        fi
    else
        log_message "INFO: Night processor already stopped gracefully - no action needed"
        
        # Still check for any orphaned containers
        local bbb_containers=$(get_active_conversion_containers)
        if [ -z "$bbb_containers" ]; then
            log_message "INFO: No active conversions found - system clean"
            return 0
        else
            log_message "INFO: Found orphaned containers, proceeding with cleanup"
        fi
    fi
    
    # Get list of active BBB-MP4 containers
    local bbb_containers=$(get_active_conversion_containers)
    
    if [ -n "$bbb_containers" ]; then
        log_message "INFO: Found active BBB-MP4 conversion containers:"
        echo "$bbb_containers" | while read -r container; do
            log_message "INFO: - $container"
        done
        
        # Give containers 2 minutes to finish naturally
        log_message "INFO: Giving containers 2 minutes to finish naturally..."
        sleep 120
        
        # Check again and stop remaining containers
        bbb_containers=$(get_active_conversion_containers)
        if [ -n "$bbb_containers" ]; then
            log_message "INFO: Stopping remaining BBB-MP4 containers..."
            echo "$bbb_containers" | while read -r container; do
                log_message "INFO: Stopping container: $container"
                docker stop "$container" || log_message "ERROR: Failed to stop $container"
                
                # Add to failed log since it was interrupted
                echo "$container" >> "$FAILED_LOG"
            done
            
            # Wait a bit more for graceful shutdown
            sleep 30
            
            # Force kill any remaining containers
            bbb_containers=$(get_active_conversion_containers)
            if [ -n "$bbb_containers" ]; then
                log_message "WARNING: Force killing remaining containers..."
                echo "$bbb_containers" | while read -r container; do
                    log_message "WARNING: Force killing container: $container"
                    docker kill "$container" 2>/dev/null || true
                done
            fi
        else
            log_message "INFO: All containers finished naturally"
        fi
    else
        log_message "INFO: No active BBB-MP4 containers found"
    fi
    
    # Clean up processing queue (move interrupted jobs back to pending)
    if [ -f "$PROCESSING_QUEUE" ] && [ -s "$PROCESSING_QUEUE" ]; then
        log_message "INFO: Moving interrupted jobs from processing back to pending queue"
        local pending_queue="/var/www/bbb-mp4/queue/pending.txt"
        
        # Prepend processing items to pending queue (so they get priority)
        if [ -f "$pending_queue" ]; then
            cat "$PROCESSING_QUEUE" "$pending_queue" > "${pending_queue}.tmp"
            mv "${pending_queue}.tmp" "$pending_queue"
        else
            cp "$PROCESSING_QUEUE" "$pending_queue"
        fi
        
        # Clear processing queue
        > "$PROCESSING_QUEUE"
        log_message "INFO: Moved $(wc -l < "$pending_queue") jobs back to pending queue"
    fi
    
    log_message "INFO: Morning shutdown completed"
}

# Run main function
main

