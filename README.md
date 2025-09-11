# 🎥 BigBlueButton MP4 with Night Queue System

> **Enhanced fork** of the original [bbb-mp4](https://github.com/manishkatyan/bbb-mp4) project with intelligent queue system

Automatically convert BigBlueButton recordings to MP4 videos with intelligent night processing to avoid CPU load during classes.

## ✨ Features

- **🌙 Night Processing**: Converts recordings during off-hours to avoid impacting live classes
- **⚙️ Configurable Schedule**: Set your own timezone and working hours
- **🔄 Queue Management**: Intelligent queue system with retry capabilities  
- **📊 Parallel Processing**: Configurable concurrent conversions (default: 2)
- **🛡️ Graceful Shutdown**: Smart stopping with conversion completion
- **📱 Download Button**: Automatic download button in BigBlueButton playback
- **🐳 Docker-based**: Isolated, reliable conversion environment

## 🏗️ How It Works

1. **Recording Published** → Added to conversion queue (no immediate CPU load)
2. **Night Time** → Queue processor starts automatically via cron
3. **Conversion** → Docker containers convert recordings to MP4 in parallel
4. **Morning** → System gracefully stops, waits for active conversions
5. **Access** → MP4 files available via download button in BigBlueButton

## 🚀 Quick Install

```bash
# Clone to your BigBlueButton server
cd /var/www
git clone https://github.com/YOUR_USERNAME/bbb-mp4.git
cd bbb-mp4

# Configure (optional - auto-detects BBB domain, has sensible defaults)
cp config.env.example config.env
nano config.env  # Edit if needed

# Install everything
sudo ./bbb-mp4-install.sh
```

## ⚙️ Configuration

All settings are in one file: `config.env`

```bash
# BigBlueButton settings (auto-detected)
BBB_DOMAIN_NAME=bbb.example.com
COPY_TO_LOCATION=/var/www/bigbluebutton-default/recording

# Timezone for working hours
TIMEZONE=Asia/Yekaterinburg

# Working hours (24-hour format)
WORK_START_HOUR=22  # 10 PM
WORK_END_HOUR=7     # 7 AM

# Performance settings
MAX_PARALLEL_JOBS=2
CONVERSION_TIMEOUT=7200
```

### 🌍 Timezone Examples
- `Asia/Yekaterinburg` (UTC+5)
- `Europe/Moscow` (UTC+3)  
- `America/New_York` (UTC-5)
- `Europe/London` (UTC+0)
- `Asia/Tokyo` (UTC+9)

## 📋 Queue Management

```bash
# Check system status
./queue-manager.sh status

# List pending recordings
./queue-manager.sh list pending

# Add recording manually
./queue-manager.sh add <meeting-id>

# Scan for new recordings
./queue-manager.sh scan

# Retry failed conversions
./queue-manager.sh retry-all

# Clear completed entries
./queue-manager.sh clear completed
```

## 🎛️ Manual Control

```bash
# Normal start (respects working hours)
systemctl start bbb-mp4-night-processor

# Force processing now (ignores time)
./night-processor.sh --force

# Stop processing
systemctl stop bbb-mp4-night-processor

# View logs
tail -f logs/night-processor.log
```

## 📊 System Status

The system shows current status including:
- ✅ **Processing hours**: Active conversion time
- ⏸️ **Outside hours**: System paused
- 🔄 **Active conversions**: Currently running jobs
- 📝 **Queue counts**: Pending, processing, completed, failed

## 🕐 Schedule Examples

### Default: Night Processing
```bash
WORK_START_HOUR=22  # 10 PM
WORK_END_HOUR=7     # 7 AM
# Processes 22:00-07:00 in your timezone
```

### Business Hours Processing  
```bash
WORK_START_HOUR=9   # 9 AM
WORK_END_HOUR=17    # 5 PM
# Processes 09:00-17:00 in your timezone
```

### Weekend Processing
Use cron to run only on weekends, or modify working hours as needed.

## 📁 File Structure

```
/var/www/bbb-mp4/
├── bbb-mp4-install.sh      # Main installer
├── night-processor.sh      # Night queue processor
├── stop-night-processor.sh # Graceful shutdown script
├── queue-manager.sh        # Queue management CLI
├── bbb_mp4.rb             # Post-publish script (queue-based)
├── bbb-mp4.sh             # Docker conversion script
├── config.env             # ⭐ Single configuration file
├── config.env.example     # Configuration template
├── queue/                 # Queue files
│   ├── pending.txt        # Waiting for conversion
│   ├── processing.txt     # Currently converting
│   ├── completed.txt      # Successfully converted
│   └── failed.txt         # Failed conversions
└── logs/                  # Log files
    ├── night-processor.log
    ├── queue.log
    ├── cron.log
    └── systemd.log
```

## 🔧 Advanced Usage

### Custom Timezone Setup
```bash
# Set any timezone
TIMEZONE=America/Los_Angeles
WORK_START_HOUR=23
WORK_END_HOUR=6
```

### High-Performance Setup
```bash
# More parallel jobs (if you have powerful server)
MAX_PARALLEL_JOBS=4

# Shorter timeout for faster failure detection
CONVERSION_TIMEOUT=3600  # 1 hour
```

### Monitoring Setup
```bash
# Watch logs in real-time
tail -f logs/night-processor.log

# Check queue status every minute
watch -n 60 './queue-manager.sh status'

# Monitor system resources
htop
docker stats
```

## 🛠️ Troubleshooting

### Queue Not Processing
```bash
# Check if in working hours
./queue-manager.sh status

# Check cron jobs
sudo -u bigbluebutton crontab -l

# Manual force run
./night-processor.sh --force
```

### Failed Conversions
```bash
# List failed recordings
./queue-manager.sh list failed

# Retry specific recording
./queue-manager.sh add <meeting-id>

# Retry all failed
./queue-manager.sh retry-all
```

### Docker Issues
```bash
# Check Docker status
systemctl status docker

# View container logs
docker logs <container-name>

# Clean up stopped containers
docker container prune
```

## 📋 Requirements

- BigBlueButton server (2.3+)
- Docker installed
- Root access for installation
- Sufficient disk space for MP4 files

## 🔄 Migration from Original bbb-mp4

If you have the original bbb-mp4 installed:

1. **Backup**: Your existing setup is automatically backed up
2. **Queue**: Existing recordings are scanned and added to queue
3. **Compatibility**: Download buttons continue to work
4. **Rollback**: Original files are saved as `.backup`

## 🆘 Support & Updates

### Getting Updates
```bash
# Pull latest changes
git pull origin main

# Re-run installer to update
sudo ./bbb-mp4-install.sh
```

### Common Issues
- **Permission denied**: Ensure `bigbluebutton` user has Docker access
- **Cron not running**: Check `sudo -u bigbluebutton crontab -l`
- **Timezone issues**: Verify with `TZ=Your/Timezone date`

## 🏆 Why Night Queue System?

- **🎯 No Impact on Classes**: Conversions happen when server is idle
- **⚡ Better Performance**: Controlled resource usage with parallel limits
- **🔄 Reliability**: Queue system with automatic retry on failures
- **📊 Monitoring**: Clear visibility into conversion status
- **🛡️ Graceful**: Smart shutdown that doesn't interrupt conversions
- **⚙️ Flexible**: Configurable for any timezone and schedule

## 🚀 <a href="https://higheredlab.com/bigbluebutton" target="_blank">Professional BigBlueButton Hosting</a>

**Stress-free BigBlueButton hosting with expert support.**

- 🖥️ Bare metal servers for HD video
- 💰 40% lower hosting costs  
- ⭐ Top-rated tech support, 100% uptime
- 🔄 Upgrade/cancel anytime
- 🆓 2 weeks free trial, no credit card needed

<a href="https://higheredlab.com/bigbluebutton" target="_blank"><strong>🚀 Start Free Trial</strong></a>

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Credits

This enhanced fork is based on the excellent work by [Manish Katyan](https://github.com/manishkatyan) and the original [bbb-mp4](https://github.com/manishkatyan/bbb-mp4) project. 

**Special thanks to:**
- 👨‍💻 **Manish Katyan** - Original bbb-mp4 creator
- 🏢 **HigherEdLab** - BigBlueButton hosting and support
- 🌍 **BigBlueButton Community** - Continued development and feedback

**Made with ❤️ for the BigBlueButton community**