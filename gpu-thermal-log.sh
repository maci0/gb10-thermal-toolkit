#!/bin/bash
# Log GPU thermals to the journal, but only when the GPU is active
# (utilization above a baseline). Invoked once per minute by a systemd timer.
THRESH=${GPU_LOG_THRESHOLD:-10}
util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -dc '0-9')
[ -z "$util" ] && exit 0
[ "$util" -lt "$THRESH" ] && exit 0
read -r temp power sm <<EOF
$(nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.sm --format=csv,noheader,nounits 2>/dev/null | head -1 | tr ',' ' ')
EOF
zones=""
for z in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$z" ] && zones="$zones$(( $(cat "$z") / 1000 ))C "
done
echo "util=${util}% gpu=${temp}C power=${power}W sm=${sm}MHz zones=[${zones% }]"
