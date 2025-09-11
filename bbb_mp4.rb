#!/usr/bin/ruby
# encoding: UTF-8
# Modified bbb_mp4.rb - adds recordings to queue instead of immediate conversion
require "optimist"
require File.expand_path('../../../lib/recordandplayback', __FILE__)

logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

opts = Optimist::options do
  opt :meeting_id, "Meeting id to add to conversion queue", :type => String
  opt :format, "Playback format name", :type => String
end

meeting_id = opts[:meeting_id]

# Load configuration from config.env
def load_config
  config_file = "/var/www/bbb-mp4/config.env"
  config = {}
  
  if File.exist?(config_file)
    File.readlines(config_file).each do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')
      
      if line.include?('=')
        key, value = line.split('=', 2)
        config[key] = value
      end
    end
  end
  
  # Set defaults
  config['BBB_MP4_DIR'] ||= "/var/www/bbb-mp4"
  config['QUEUE_DIR'] ||= "#{config['BBB_MP4_DIR']}/queue"
  config['LOG_DIR'] ||= "#{config['BBB_MP4_DIR']}/logs"
  config['COPY_TO_LOCATION'] ||= "/var/www/bigbluebutton-default/recording"
  config['PRESENTATION_DIR'] ||= "/var/bigbluebutton/published/presentation"
  
  config
end

config = load_config

# Paths from configuration
queue_dir = config['QUEUE_DIR']
pending_queue = "#{queue_dir}/pending.txt"
mp4_output_dir = config['COPY_TO_LOCATION']
presentation_dir = config['PRESENTATION_DIR']

begin
  # Check if recording exists in published presentations
  recording_path = "#{presentation_dir}/#{meeting_id}"
  unless Dir.exist?(recording_path)
    BigBlueButton.logger.warn("Recording not found in published presentations: #{meeting_id}")
    exit 1
  end

  # Check if MP4 already exists
  mp4_file = "#{mp4_output_dir}/#{meeting_id}.mp4"
  if File.exist?(mp4_file)
    BigBlueButton.logger.info("MP4 already exists for #{meeting_id}, skipping queue")
    exit 0
  end

  # Create queue directory if it doesn't exist
  Dir.mkdir(queue_dir) unless Dir.exist?(queue_dir)

  # Check if already in queue
  if File.exist?(pending_queue)
    queue_content = File.read(pending_queue)
    if queue_content.include?(meeting_id)
      BigBlueButton.logger.info("Meeting #{meeting_id} already in queue")
      exit 0
    end
  end

  # Add to queue (append to end of file)
  File.open(pending_queue, 'a') do |file|
    file.puts meeting_id
  end

  BigBlueButton.logger.info("Added #{meeting_id} to conversion queue")

rescue => e
  BigBlueButton.logger.error("Error adding #{meeting_id} to queue: #{e.message}")
  exit 1
end
