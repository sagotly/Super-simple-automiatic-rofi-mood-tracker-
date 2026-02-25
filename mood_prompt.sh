#!/usr/bin/env bash

set -u

BASE_DIR="$HOME/.config/rofi/mood"
THEME="$HOME/.config/rofi/theme.rasi"
CSV_FILE="$BASE_DIR/mood_log.csv"
LOCK_FILE="$BASE_DIR/.mood_prompt.lock"
FORCE_MODE=0

for arg in "$@"; do
    case "$arg" in
        --force)
            FORCE_MODE=1
            ;;
    esac
done

mkdir -p "$BASE_DIR"

# Prevent overlapping cron runs from opening multiple rofi dialogs.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    exit 0
fi

day_key_iso="$(date +%Y-%m-%d)"
datetime_now="$(date +'%d-%m-%Y %H:%M')"
hour_now="$(date +%H)"
HEADER_NEW="date,mood,apathy,health,swag,anxiety,anger"
HEADER_OLD_V1="date,mood,apathy,health,swag"
HEADER_OLD_V2="date,mood,apathy,health,swag,anxiety"
HEADER_OLD_V3="date,mood,apathy,health,swag,anxiety,anger"
HEADER_OLD_V4="date,mood,apathy,health,swag,anxiety,anger,slot"

if [ "$hour_now" -ge 12 ] && [ "$hour_now" -lt 19 ]; then
    window_start_str="$day_key_iso 12:00"
    window_end_str="$day_key_iso 19:00"
elif [ "$hour_now" -ge 19 ]; then
    window_start_str="$day_key_iso 19:00"
    window_end_str="$(date -d 'tomorrow' +%Y-%m-%d) 12:00"
else
    window_start_str="$(date -d 'yesterday' +%Y-%m-%d) 19:00"
    window_end_str="$day_key_iso 12:00"
fi

window_start_ts="$(date -d "$window_start_str" +%s 2>/dev/null || true)"
window_end_ts="$(date -d "$window_end_str" +%s 2>/dev/null || true)"
[ -z "$window_start_ts" ] && exit 0
[ -z "$window_end_ts" ] && exit 0

if [ ! -f "$CSV_FILE" ]; then
    printf "%s\n" "$HEADER_NEW" > "$CSV_FILE"
else
    first_line="$(sed -n '1p' "$CSV_FILE")"
    if [ "$first_line" = "$HEADER_OLD_V1" ]; then
        tmp_file="$(mktemp)"
        {
            printf "%s\n" "$HEADER_NEW"
            awk 'NR > 1 { printf "%s,,\n", $0 }' "$CSV_FILE"
        } > "$tmp_file"
        mv "$tmp_file" "$CSV_FILE"
    elif [ "$first_line" = "$HEADER_OLD_V2" ]; then
        tmp_file="$(mktemp)"
        {
            printf "%s\n" "$HEADER_NEW"
            awk 'NR > 1 { printf "%s,\n", $0 }' "$CSV_FILE"
        } > "$tmp_file"
        mv "$tmp_file" "$CSV_FILE"
    elif [ "$first_line" = "$HEADER_OLD_V4" ]; then
        tmp_file="$(mktemp)"
        {
            printf "%s\n" "$HEADER_NEW"
            awk -F, '
                NR > 1 {
                    printf "%s,%s,%s,%s,%s,%s,%s\n", $1, $2, $3, $4, $5, $6, $7
                }
            ' "$CSV_FILE"
        } > "$tmp_file"
        mv "$tmp_file" "$CSV_FILE"
    elif [ "$first_line" = "$HEADER_OLD_V3" ]; then
        :
    else
        # Unknown header: keep file untouched and continue with the new format for new rows.
        :
    fi
fi

entry_exists_in_window() {
    [ ! -f "$CSV_FILE" ] && return 1
    while IFS=, read -r date_col _rest; do
        [ "$date_col" = "date" ] && continue
        [ -z "$date_col" ] && continue

        rec_ts=""
        if [[ "$date_col" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{4}[[:space:]][0-9]{2}:[0-9]{2}$ ]]; then
            # CSV stores human format dd-mm-yyyy HH:MM, convert to ISO for GNU date parsing.
            rec_iso="$(printf "%s\n" "$date_col" | sed -E 's#^([0-9]{2})-([0-9]{2})-([0-9]{4}) ([0-9]{2}:[0-9]{2})$#\3-\2-\1 \4#')"
            rec_ts="$(date -d "$rec_iso" +%s 2>/dev/null || true)"
        elif [[ "$date_col" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{4}$ ]]; then
            # Old rows without time are treated as noon entries.
            rec_iso="$(printf "%s\n" "$date_col" | sed -E 's#^([0-9]{2})-([0-9]{2})-([0-9]{4})$#\3-\2-\1#')"
            rec_ts="$(date -d "$rec_iso 12:00" +%s 2>/dev/null || true)"
        fi

        [ -z "$rec_ts" ] && continue
        if [ "$rec_ts" -ge "$window_start_ts" ] && [ "$rec_ts" -lt "$window_end_ts" ]; then
            return 0
        fi
    done < "$CSV_FILE"
    return 1
}

if [ "$FORCE_MODE" -eq 0 ] && entry_exists_in_window; then
    exit 0
fi

ask_rating() {
    local label="$1"
    local value
    local options

    options="$(printf "1\n2\n3\n4\n5\n6\n7\n8\n9\n10")"

    while true; do
        value="$(printf "%s\n" "$options" | rofi -dmenu -i -p "$label (1-10)" -theme "$THEME" -no-custom)"

        if [ -z "$value" ]; then
            return 1
        fi

        if [[ "$value" =~ ^([1-9]|10)$ ]]; then
            printf "%s\n" "$value"
            return 0
        fi
    done
}

mood="$(ask_rating "Mood")" || exit 1
apathy="$(ask_rating "Apathy")" || exit 1
health="$(ask_rating "Health")" || exit 1
swag="$(ask_rating "Swag")" || exit 1
anxiety="$(ask_rating "Anxiety")" || exit 1
anger="$(ask_rating "Anger")" || exit 1

# Check again before append in case another process completed this time window while dialogs were open.
if [ "$FORCE_MODE" -eq 0 ] && entry_exists_in_window; then
    exit 0
fi

printf "%s,%s,%s,%s,%s,%s,%s\n" "$datetime_now" "$mood" "$apathy" "$health" "$swag" "$anxiety" "$anger" >> "$CSV_FILE"
