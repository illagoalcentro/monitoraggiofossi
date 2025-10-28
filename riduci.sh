#!/usr/bin/env bash
# resize_jpgs.sh
# Ridimensiona ricorsivamente tutte le immagini jpg/jpeg a max 1200x1200 (no upscaling)
# Log CSV su file + stdout, con errori dettagliati da ImageMagick

set -u
set -o pipefail

ROOT_DIR="${1:-.}"
LOG_FILE="${2:-./resize_images.log}"
MAX_PIXELS=1200

declare -a IDENTIFY_CMD
declare -a CONVERT_CMD
RESIZE_ARG="${MAX_PIXELS}x${MAX_PIXELS}>"

# --- Rilevamento versione ImageMagick ---
if command -v magick >/dev/null 2>&1; then
  IDENTIFY_CMD=(magick identify)
  CONVERT_CMD=(magick)
  # In IM7 serve il backslash
  RESIZE_ARG="${MAX_PIXELS}x${MAX_PIXELS}\\>"
elif command -v identify >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
  IDENTIFY_CMD=(identify)
  CONVERT_CMD=(convert)
  # In IM6 NO backslash
  RESIZE_ARG="${MAX_PIXELS}x${MAX_PIXELS}>"
else
  echo "Errore: ImageMagick non trovato. Installa con: sudo apt install imagemagick" >&2
  exit 2
fi

if [ ! -e "$LOG_FILE" ]; then
  printf "timestamp,filepath,orig_width,orig_height,orig_bytes,new_width,new_height,new_bytes,status,message\n" > "$LOG_FILE"
fi

csv_escape() {
  local s="$1"; s="${s//\"/\"\"}"; printf '"%s"' "$s"
}

write_log_line() {
  local line="$1"
  printf '%s\n' "$line" | tee -a "$LOG_FILE"
}

while IFS= read -r -d '' file; do
  timestamp="$(date --iso-8601=seconds)"
  identify_out="$("${IDENTIFY_CMD[@]}" -format "%w %h" "$file" 2>&1)" || identify_status=$? || true
  orig_bytes=$(stat -c%s -- "$file" 2>/dev/null || echo 0)

  if [ -z "${identify_out:-}" ] || [ "${identify_status:-0}" -ne 0 ]; then
    status="error"
    message="identify_failed: ${identify_out:-unknown}"
    line="$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s' \
      "$timestamp" "$(csv_escape "$file")" 0 0 "$orig_bytes" 0 0 0 "$(csv_escape "$status:$message")")"
    write_log_line "$line"
    continue
  fi

  orig_w=$(awk '{print $1}' <<<"$identify_out")
  orig_h=$(awk '{print $2}' <<<"$identify_out")

  if [ "$orig_w" -le "$MAX_PIXELS" ] && [ "$orig_h" -le "$MAX_PIXELS" ]; then
    status="skipped"
    message="already_within_limits"
    line="$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s' \
      "$timestamp" "$(csv_escape "$file")" "$orig_w" "$orig_h" "$orig_bytes" "$orig_w" "$orig_h" "$orig_bytes" "$(csv_escape "$status:$message")")"
    write_log_line "$line"
    continue
  fi

  dir=$(dirname -- "$file")
  tmpfile="$(mktemp "$dir/.tmp_resize.XXXXXX")" || tmpfile="/tmp/.tmp_resize.$$.$RANDOM"

  convert_out="$("${CONVERT_CMD[@]}" "$file" -resize "$RESIZE_ARG" "$tmpfile" 2>&1)" || convert_status=$? || true

  if [ "${convert_status:-0}" -ne 0 ]; then
    rm -f "$tmpfile"
    status="error"
    message="convert_failed: ${convert_out:-unknown}"
    line="$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s' \
      "$timestamp" "$(csv_escape "$file")" "$orig_w" "$orig_h" "$orig_bytes" 0 0 0 "$(csv_escape "$status:$message")")"
    write_log_line "$line"
    continue
  fi

  if mv -f "$tmpfile" "$file"; then
    new_identify_out="$("${IDENTIFY_CMD[@]}" -format "%w %h" "$file" 2>&1)" || true
    new_w=$(awk '{print $1}' <<<"$new_identify_out")
    new_h=$(awk '{print $2}' <<<"$new_identify_out")
    new_bytes=$(stat -c%s -- "$file" 2>/dev/null || echo 0)
    status="resized"
    message="ok"
  else
    rm -f "$tmpfile"
    status="error"
    message="mv_failed"
    new_w=0; new_h=0; new_bytes=0
  fi

  line="$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s' \
    "$timestamp" "$(csv_escape "$file")" "$orig_w" "$orig_h" "$orig_bytes" "$new_w" "$new_h" "$new_bytes" "$(csv_escape "$status:$message")")"
  write_log_line "$line"

done < <(find "$ROOT_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0)
