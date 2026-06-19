#!/bin/bash
# Dynamic GPU clock governor for GB10 / ASUS GX10.
# The graphics-clock cap (nvidia-smi -lgc) is the only thermal lever on GB10
# (no OS fan control; nvidia-smi -pl is N/A). This loop watches the GPU temp and
# the hottest board/acpitz zone, steps the cap DOWN when hot and back UP when
# cool, with hysteresis, to hold temps in a safe band and dodge the OCP/thermal
# power-off. Logs only on a change (quiet when stable). Stdout -> journal/docker.
set -u
MIN_CLK=${MIN_CLK:-1400}     # floor
MAX_CLK=${MAX_CLK:-2000}     # ceiling (your chosen safe cap)
STEP=${STEP:-100}
GPU_HI=${GPU_HI:-86}         # step down above this GPU temp (C)
GPU_LO=${GPU_LO:-80}         # step up below this (and zone below ZONE_LO)
ZONE_HI=${ZONE_HI:-90}       # step down above this board (acpitz) temp (C)
ZONE_LO=${ZONE_LO:-84}
INTERVAL=${INTERVAL:-5}      # seconds

MAX_ITERS=${MAX_ITERS:-17280}   # ~24h at 5s; clean exit -> docker --restart respawns fresh

timeout 10 nvidia-smi -pm 1 >/dev/null 2>&1
cur=$MAX_CLK
timeout 10 nvidia-smi -lgc 0,$cur >/dev/null 2>&1
echo "governor start: cap=${cur} band[min=${MIN_CLK} max=${MAX_CLK}] gpuHi=${GPU_HI} zoneHi=${ZONE_HI} step=${STEP} interval=${INTERVAL}s"

iter=0
while [ "$iter" -lt "$MAX_ITERS" ]; do
  iter=$(( iter + 1 ))
  gpu=$(timeout 10 nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -dc '0-9')
  zone=0
  for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    v=$(( $(cat "$z") / 1000 )); [ "$v" -gt "$zone" ] && zone=$v
  done
  if [ -z "$gpu" ]; then sleep "$INTERVAL"; continue; fi
  new=$cur
  if [ "$gpu" -ge "$GPU_HI" ] || [ "$zone" -ge "$ZONE_HI" ]; then
    new=$(( cur - STEP )); [ "$new" -lt "$MIN_CLK" ] && new=$MIN_CLK
  elif [ "$gpu" -le "$GPU_LO" ] && [ "$zone" -le "$ZONE_LO" ]; then
    new=$(( cur + STEP )); [ "$new" -gt "$MAX_CLK" ] && new=$MAX_CLK
  fi
  if [ "$new" -ne "$cur" ]; then
    cur=$new
    timeout 10 nvidia-smi -lgc 0,$cur >/dev/null 2>&1
    echo "$(date '+%H:%M:%S') gpu=${gpu}C zone=${zone}C -> cap=${cur}MHz"
  fi
  sleep "$INTERVAL"
done
echo "governor: reached MAX_ITERS=${MAX_ITERS}, exiting for clean restart"
