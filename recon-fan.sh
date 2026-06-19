#!/bin/bash
# recon-fan.sh - probe every OS-side channel for a fan-RPM read path on GB10/GX10.
# Needs root (ACPI table dump + debugfs). See FAN_MONITORING.md for the verdict.
# Requires: acpica-tools, i2c-tools, lm-sensors (apt install acpica-tools i2c-tools lm-sensors).
set -u
echo "== NVML fan =="
nvidia-smi --query-gpu=fan.speed,temperature.gpu --format=csv 2>/dev/null

echo "== hwmon names =="
cat /sys/class/hwmon/hwmon*/name 2>/dev/null

echo "== ACPI: Fan / _FST / tach methods =="
d=$(mktemp -d); ( cd "$d" && acpidump -b >/dev/null 2>&1 && for f in *.dat; do iasl -d "$f" >/dev/null 2>&1; done
  grep -hiE "fan|_FST|_FIF|_FPS|tach|rpm" ./*.dsl 2>/dev/null | grep -ivE "^ *//" | sort -u | head -25 )
rm -rf "$d"

echo "== device tree fan/pwm/tach/ec =="
find /proc/device-tree -iname '*fan*' -o -iname '*pwm*' -o -iname '*tach*' -o -iname '*ec*' 2>/dev/null | head

echo "== SCMI =="
mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo "debugfs: $(ls -A /sys/kernel/debug/scmi/ 2>/dev/null || echo empty)"
echo "devices: $(ls /sys/bus/scmi/devices/ 2>/dev/null || echo none)"

echo "== I2C buses =="
i2cdetect -l 2>/dev/null

echo "== lm-sensors =="
sensors 2>/dev/null | grep -iE "fan|rpm" || echo "no fan sensor"
