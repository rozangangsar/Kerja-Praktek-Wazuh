#!/usr/bin/env bash
set -euo pipefail

# Simple RSS sampler for a process name.
# Output format (CSV): epoch,pid,rss_kb

PROC_NAME="${1:-wazuh-analysisd}"
DURATION_SEC="${2:-60}"
INTERVAL_SEC="${3:-1}"
OUT_FILE="${4:-/tmp/${PROC_NAME}_rss_$(date +%Y%m%d_%H%M%S).csv}"

if ! [[ "$DURATION_SEC" =~ ^[0-9]+$ ]] || ! [[ "$INTERVAL_SEC" =~ ^[0-9]+$ ]] || [ "$INTERVAL_SEC" -eq 0 ]; then
  echo "Usage: $0 [process_name] [duration_sec] [interval_sec] [output_csv]" >&2
  exit 1
fi

echo "epoch,pid,rss_kb" > "$OUT_FILE"

SAMPLES=$((DURATION_SEC / INTERVAL_SEC))
if [ "$SAMPLES" -le 0 ]; then
  echo "duration_sec must be >= interval_sec" >&2
  exit 1
fi

echo "Sampling '$PROC_NAME' for ${DURATION_SEC}s every ${INTERVAL_SEC}s..."

for ((i=0; i<SAMPLES; i++)); do
  TS="$(date +%s)"
  PIDS="$(pgrep -x "$PROC_NAME" || true)"

  if [ -n "$PIDS" ]; then
    while IFS= read -r PID; do
      [ -z "$PID" ] && continue
      RSS_KB="$(awk '/^VmRSS:/ {print $2}' "/proc/$PID/status" 2>/dev/null || echo 0)"
      echo "${TS},${PID},${RSS_KB}" >> "$OUT_FILE"
    done <<< "$PIDS"
  fi

  sleep "$INTERVAL_SEC"
done

echo "Done. CSV: $OUT_FILE"

awk -F',' '
  NR>1 && $3 ~ /^[0-9]+$/ {
    c+=1; s+=$3; if ($3>m) m=$3;
  }
  END {
    if (c==0) {
      print "No samples collected (process not found during window).";
    } else {
      printf "Samples: %d\nAvg RSS: %.2f MB\nMax RSS: %.2f MB\n", c, (s/c)/1024, m/1024;
    }
  }
' "$OUT_FILE"
