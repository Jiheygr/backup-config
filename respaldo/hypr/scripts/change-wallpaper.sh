#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers/Videos"
STATE_FILE="$HOME/.cache/mpvpaper_index"

mapfile -t VIDEOS < <(find "$WALLPAPER_DIR" -type f | sort)

TOTAL=${#VIDEOS[@]}
(( TOTAL == 0 )) && exit 1

if [[ -f "$STATE_FILE" ]]; then
    INDEX=$(cat "$STATE_FILE")
else
    INDEX=0
fi

INDEX=$(( (INDEX + 1) % TOTAL ))
echo "$INDEX" > "$STATE_FILE"

VIDEO="${VIDEOS[$INDEX]}"

pkill mpvpaper
sleep 0.3

mpvpaper -o "no-audio --loop" '*' "$VIDEO" &
