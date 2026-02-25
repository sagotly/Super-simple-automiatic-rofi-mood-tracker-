#!/usr/bin/env bash

set -eu

TAG="# rofi-mood-tracker"
SCRIPT_PATH="$HOME/.config/rofi/mood/mood_prompt.sh"
USER_ID="$(id -u)"
CRON_LINE="*/10 * * * * DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/${USER_ID} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${USER_ID}/bus ${SCRIPT_PATH} ${TAG}"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

crontab -l 2>/dev/null | grep -v "rofi-mood-tracker" > "$tmp_file" || true
printf "%s\n" "$CRON_LINE" >> "$tmp_file"
crontab "$tmp_file"

printf "Installed persistent cron entry (survives reboot):\n%s\n" "$CRON_LINE"
