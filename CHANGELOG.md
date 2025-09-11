# 🔄 Changelog

## v2.0.0 - Enhanced Fork with Night Queue System (2024)

**Based on:** [manishkatyan/bbb-mp4](https://github.com/manishkatyan/bbb-mp4) - Enhanced with intelligent queue system

### 🌟 Major Features Added
- **Night Queue Processing**: Intelligent scheduling to avoid CPU load during classes
- **Configurable Timezone**: Support for any timezone via `config.env`
- **Flexible Working Hours**: Set custom processing hours (default: 22:00-07:00)
- **Queue Management System**: Complete CLI tool for queue operations
- **Graceful Shutdown**: Smart stopping with 15-minute safety backup
- **Force Mode**: Manual processing override for urgent conversions

### ⚙️ Configuration System
- **Environment-based Config**: `config.env` for all settings
- **Auto-timezone Detection**: Configurable timezone support
- **Parallel Job Control**: Adjustable concurrent conversions (default: 2)
- **Timeout Management**: Configurable conversion timeouts
- **Flexible Scheduling**: Support for both overnight and daytime processing

### 🛠️ Technical Improvements
- **Unified Installation**: Single `bbb-mp4-install.sh` installer
- **Systemd Integration**: Professional service management
- **Enhanced Logging**: Comprehensive logging system
- **Error Handling**: Robust retry mechanisms
- **Resource Management**: Controlled CPU and memory usage

### 📋 Queue Management
- **Status Monitoring**: Real-time system status
- **Queue Operations**: Add, remove, retry, clear operations
- **Batch Processing**: Scan and queue existing recordings
- **Failure Recovery**: Automatic retry system for failed conversions

### 🔧 Developer Experience
- **Modern README**: Comprehensive documentation with examples
- **Configuration Templates**: `config.env.example` with all options
- **Troubleshooting Guide**: Common issues and solutions
- **Migration Support**: Seamless upgrade from original bbb-mp4

### 🗂️ File Structure Changes
- **Replaced**: `bbb_mp4_queue.rb` → `bbb_mp4.rb` (main post-publish script)
- **Added**: `night-processor.sh` (main queue processor)
- **Added**: `stop-night-processor.sh` (graceful shutdown)
- **Added**: `queue-manager.sh` (CLI management tool)
- **Added**: `config.env.example` (configuration template)
- **Updated**: `bbb-mp4-install.sh` (unified installer)
- **Updated**: `README.md` (modern documentation)
- **Removed**: Legacy night queue files

### 🌍 Timezone Support
- **Asia/Yekaterinburg** (UTC+5) - Default
- **Europe/Moscow** (UTC+3)
- **America/New_York** (UTC-5)
- **Europe/London** (UTC+0)
- **Any valid timezone** via configuration

### 📊 System Integration
- **Cron Automation**: Automatic daily scheduling
- **Systemd Service**: Professional service management  
- **Docker Integration**: Isolated conversion environment
- **BigBlueButton Compatible**: Seamless integration with BBB

### 🔄 Migration Path
- **Backward Compatible**: Existing setups continue working
- **Automatic Backup**: Original files preserved
- **Queue Migration**: Existing recordings auto-queued
- **Configuration Migration**: Settings preserved and enhanced

---

## v1.x.x - Original Version

### Features
- Direct post-publish conversion
- Docker-based processing
- Download button integration
- Basic MP4 conversion

### Limitations
- Immediate CPU load during classes
- No scheduling capabilities
- Limited error handling
- No queue management
