#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   tools/monitor_ram_csv.sh [output_csv] [interval_seconds] [duration_minutes]
#
# Example:
#   tools/monitor_ram_csv.sh /tmp/wazuh_ram_$(date +%F_%H%M).csv 30 60

OUTFILE="${1:-/tmp/wazuh_ram_$(date +%F_%H%M%S).csv}"
INTERVAL="${2:-30}"
DURATION_MIN="${3:-60}"

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || ! [[ "$DURATION_MIN" =~ ^[0-9]+$ ]]; then
  echo "interval_seconds and duration_minutes must be integers" >&2
  exit 1
fi

SAMPLES=$(( (DURATION_MIN * 60) / INTERVAL ))
if (( SAMPLES < 1 )); then
  SAMPLES=1
fi

echo "timestamp,mem_used_mib,mem_avail_mib,swap_used_mib,load1,indexer_pid,indexer_rss_kib,modulesd_pid,modulesd_rss_kib,analysisd_pid,analysisd_rss_kib,wazuhdb_pid,wazuhdb_rss_kib,dashboard_pid,dashboard_rss_kib" > "$OUTFILE"

get_pid_by_cmd() {
  local pattern="$1"
  pgrep -f "$pattern" | head -n 1 || true
}

get_rss_kib() {
  local pid="$1"
  if [[ -n "$pid" ]] && [[ -r "/proc/$pid/status" ]]; then
    awk '/^VmRSS:/ {print $2; found=1; exit} END {if (!found) print ""}' "/proc/$pid/status" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

for ((i=0; i<SAMPLES; i++)); do
  ts="$(date '+%F %T')"

  # Memory snapshot
  read -r mem_used mem_avail swap_used < <(free -m | awk '
    /^Mem:/ {u=$3; a=$7}
    /^Swap:/ {s=$3}
    END {print u, a, s}
  ')
  load1="$(awk '{print $1}' /proc/loadavg)"

  # PIDs
  idx_pid="$(get_pid_by_cmd '/usr/share/wazuh-indexer/jdk/bin/java')"
  mod_pid="$(get_pid_by_cmd '/var/ossec/bin/wazuh-modulesd')"
  ana_pid="$(get_pid_by_cmd '/var/ossec/bin/wazuh-analysisd')"
  db_pid="$(get_pid_by_cmd '/var/ossec/bin/wazuh-db')"
  dash_pid="$(get_pid_by_cmd '/usr/share/wazuh-dashboard')"

  # RSS (KiB)
  idx_rss="$(get_rss_kib "$idx_pid")"
  mod_rss="$(get_rss_kib "$mod_pid")"
  ana_rss="$(get_rss_kib "$ana_pid")"
  db_rss="$(get_rss_kib "$db_pid")"
  dash_rss="$(get_rss_kib "$dash_pid")"

  echo "$ts,$mem_used,$mem_avail,$swap_used,$load1,$idx_pid,$idx_rss,$mod_pid,$mod_rss,$ana_pid,$ana_rss,$db_pid,$db_rss,$dash_pid,$dash_rss" >> "$OUTFILE"
  sleep "$INTERVAL"
done

echo "Done. CSV saved to: $OUTFILE"
