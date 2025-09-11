# BBB MP4 Night Queue System

This is an extension to the original bbb-mp4 project that implements delayed conversion processing to avoid CPU load during daytime classes.

## What's New

Instead of converting recordings immediately after publication, this system:

- **Queues recordings** for later processing
- **Processes conversions at night** (22:00-07:00) 
- **Limits parallel jobs** to maximum 2 conversions simultaneously
- **Provides queue management** tools for monitoring and control

## Architecture

### Components

1. **`bbb_mp4_queue.rb`** - Modified post-publish script that adds recordings to queue
2. **`night-processor.sh`** - Main processor that runs scheduled conversions
3. **`stop-night-processor.sh`** - Morning shutdown script
4. **`queue-manager.sh`** - Command-line tool for queue management
5. **`install-night-queue.sh`** - Installation script

### Queue System

- **Pending Queue** (`queue/pending.txt`) - Recordings waiting for conversion
- **Processing Queue** (`queue/processing.txt`) - Currently converting recordings  
- **Completed Log** (`queue/completed.txt`) - Successfully converted recordings
- **Failed Log** (`queue/failed.txt`) - Failed conversion attempts

## Installation

### Prerequisites

1. Original bbb-mp4 must be installed and working
2. BigBlueButton server with Docker support
3. Root access for installation

### Install

```bash
# Navigate to your bbb-mp4 directory
cd /var/www/bbb-mp4

# Run the installation script
sudo ./install-night-queue.sh
```

The installer will:
- Backup original files
- Create queue directories
- Install new post-publish script
- Setup cron jobs (22:00 start, 07:00 stop)
- Create systemd service
- Scan existing recordings

## Usage

### Queue Management

```bash
# Check system status
./queue-manager.sh status

# List pending recordings
./queue-manager.sh list pending

# Add specific recording to queue
./queue-manager.sh add abc123...def456-1234567890123

# Scan for new recordings
./queue-manager.sh scan

# Retry all failed conversions
./queue-manager.sh retry-all

# Show active conversions
./queue-manager.sh active
```

### Manual Control

```bash
# Start night processor manually (for testing)
sudo systemctl start bbb-mp4-night-processor

# Stop night processor
sudo systemctl stop bbb-mp4-night-processor

# View logs
tail -f /var/www/bbb-mp4/logs/night-processor.log
```

### Monitoring

```bash
# Watch queue status
watch ./queue-manager.sh status

# Monitor active Docker containers
docker ps --filter "ancestor=manishkatyan/bbb-mp4"

# View cron logs
tail -f /var/www/bbb-mp4/logs/cron.log
```

## Configuration

### Timing
- **Start**: 22:00 daily (configured in cron)
- **Stop**: 07:00 daily (configured in cron)
- **Max Parallel**: 2 conversions (configurable in `night-processor.sh`)

### Paths
- **Queue Directory**: `/var/www/bbb-mp4/queue/`
- **Log Directory**: `/var/www/bbb-mp4/logs/`
- **Source Recordings**: `/var/bigbluebutton/published/presentation/`
- **MP4 Output**: `/var/www/bigbluebutton-default/recording/`

## Troubleshooting

### Common Issues

1. **No recordings in queue**
   ```bash
   ./queue-manager.sh scan  # Scan for new recordings
   ```

2. **Conversions not starting**
   - Check time (only runs 22:00-07:00)
   - Check Docker service: `systemctl status docker`
   - Check logs: `tail -f /var/www/bbb-mp4/logs/night-processor.log`

3. **Failed conversions**
   ```bash
   ./queue-manager.sh list failed    # See failed recordings
   ./queue-manager.sh retry-all      # Retry all failed
   ```

4. **Permission issues**
   ```bash
   sudo chown -R bigbluebutton:bigbluebutton /var/www/bbb-mp4
   ```

### Log Files

- **Night Processor**: `/var/www/bbb-mp4/logs/night-processor.log`
- **Cron Jobs**: `/var/www/bbb-mp4/logs/cron.log`
- **Systemd Service**: `/var/www/bbb-mp4/logs/systemd.log`
- **BBB Post-Publish**: `/var/log/bigbluebutton/post_publish.log`

## Reverting to Original System

To go back to immediate conversions:

```bash
# Restore original post-publish script
sudo cp /usr/local/bigbluebutton/core/scripts/post_publish/bbb_mp4.rb.backup.* \
        /usr/local/bigbluebutton/core/scripts/post_publish/bbb_mp4.rb

# Remove cron jobs
sudo -u bigbluebutton crontab -l | grep -v "night-processor" | sudo -u bigbluebutton crontab -

# Stop and disable systemd service
sudo systemctl stop bbb-mp4-night-processor
sudo systemctl disable bbb-mp4-night-processor
```

## Safety Features

- **Container Isolation**: Only manages containers with `manishkatyan/bbb-mp4` image
- **Meeting ID Validation**: Strict format validation prevents accidental operations
- **Graceful Shutdown**: Morning stop script allows conversions to complete naturally
- **Queue Recovery**: Interrupted jobs are moved back to pending queue
- **Timeout Protection**: 2-hour timeout prevents stuck conversions

## Performance Impact

- **CPU Usage**: Limited to 2 parallel ffmpeg processes maximum
- **Memory**: Each conversion uses ~500MB-1GB RAM
- **Disk I/O**: Sequential processing reduces disk contention
- **Network**: No additional network overhead

This system ensures your BigBlueButton server remains responsive during daytime classes while still processing all recordings overnight.

