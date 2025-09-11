#!/bin/bash

# Load configuration from config.env
BBB_MP4_DIR="${BBB_MP4_DIR:-/var/www/bbb-mp4}"
CONFIG_FILE="$BBB_MP4_DIR/config.env"

# Load config.env if exists
if [ -f "$CONFIG_FILE" ]; then
    set -a
    source "$CONFIG_FILE"
    set +a
else
    # Fallback defaults
    BBB_DOMAIN_NAME="${BBB_DOMAIN_NAME:-bbb.example.com}"
    COPY_TO_LOCATION="${COPY_TO_LOCATION:-/var/www/bigbluebutton-default/recording}"
fi

MEETING_ID=$1

echo "converting $MEETING_ID to mp4" |  systemd-cat -p warning -t bbb-mp4

docker run --rm -d \
                --name $MEETING_ID \
                -v $COPY_TO_LOCATION:/usr/src/app/processed \
                --env REC_URL=https://$BBB_DOMAIN_NAME/playback/presentation/2.3/$MEETING_ID \
                manishkatyan/bbb-mp4
