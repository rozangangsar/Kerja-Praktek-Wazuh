#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <before_csv> <after_csv>" >&2
  exit 1
fi

BEFORE_CSV="$1"
AFTER_CSV="$2"

if [ ! -f "$BEFORE_CSV" ]; then
  echo "before_csv not found: $BEFORE_CSV" >&2
  exit 1
fi

if [ ! -f "$AFTER_CSV" ]; then
  echo "after_csv not found: $AFTER_CSV" >&2
  exit 1
fi

calc_stats() {
  local csv="$1"
  awk -F',' '
    NR>1 && $3 ~ /^[0-9]+$/ {
      c+=1; s+=$3;
      if ($3>max) max=$3;
      if (min==0 || $3<min) min=$3;
    }
    END {
      if (c==0) {
        print "0,0,0,0";
      } else {
        printf "%d,%.6f,%.6f,%.6f\n", c, (s/c)/1024, max/1024, min/1024;
      }
    }
  ' "$csv"
}

IFS=',' read -r b_count b_avg_mb b_max_mb b_min_mb <<< "$(calc_stats "$BEFORE_CSV")"
IFS=',' read -r a_count a_avg_mb a_max_mb a_min_mb <<< "$(calc_stats "$AFTER_CSV")"

if [ "$b_count" -eq 0 ] || [ "$a_count" -eq 0 ]; then
  echo "No valid samples in one of the files."
  echo "before samples: $b_count, after samples: $a_count"
  exit 1
fi

calc_delta_pct() {
  local before="$1"
  local after="$2"
  awk -v b="$before" -v a="$after" 'BEGIN {
    if (b == 0) {
      print "0.00";
    } else {
      printf "%.2f", ((a - b) / b) * 100.0;
    }
  }'
}

delta_avg_mb="$(awk -v b="$b_avg_mb" -v a="$a_avg_mb" 'BEGIN { printf "%.2f", a-b }')"
delta_max_mb="$(awk -v b="$b_max_mb" -v a="$a_max_mb" 'BEGIN { printf "%.2f", a-b }')"
delta_min_mb="$(awk -v b="$b_min_mb" -v a="$a_min_mb" 'BEGIN { printf "%.2f", a-b }')"

delta_avg_pct="$(calc_delta_pct "$b_avg_mb" "$a_avg_mb")"
delta_max_pct="$(calc_delta_pct "$b_max_mb" "$a_max_mb")"
delta_min_pct="$(calc_delta_pct "$b_min_mb" "$a_min_mb")"

echo "=== RSS Comparison (MB) ==="
echo "Before file : $BEFORE_CSV"
echo "After file  : $AFTER_CSV"
echo
printf "%-12s %-12s %-12s %-12s %-12s\n" "Metric" "Before" "After" "Delta" "Delta(%)"
printf "%-12s %-12.2f %-12.2f %-12s %-12s\n" "Average" "$b_avg_mb" "$a_avg_mb" "$delta_avg_mb" "$delta_avg_pct"
printf "%-12s %-12.2f %-12.2f %-12s %-12s\n" "Maximum" "$b_max_mb" "$a_max_mb" "$delta_max_mb" "$delta_max_pct"
printf "%-12s %-12.2f %-12.2f %-12s %-12s\n" "Minimum" "$b_min_mb" "$a_min_mb" "$delta_min_mb" "$delta_min_pct"
echo
echo "Samples: before=$b_count after=$a_count"

if awk -v d="$delta_avg_mb" 'BEGIN { exit !(d < 0) }'; then
  echo "Result: Average RSS improved (lower than before)."
elif awk -v d="$delta_avg_mb" 'BEGIN { exit !(d > 0) }'; then
  echo "Result: Average RSS regressed (higher than before)."
else
  echo "Result: Average RSS unchanged."
fi
