#!/bin/bash
# Deploy the governor as an auto-restarting container.
# No sudo needed (docker group), survives reboot via the restart policy.
# nvidia-smi is injected into the container by the nvidia container runtime (--gpus).
set -e
IMG=${IMG:-ubuntu:24.04}
DIR=$(cd "$(dirname "$0")" && pwd)
docker rm -f gpu-governor 2>/dev/null || true
docker run -d --name gpu-governor --privileged --gpus all --restart unless-stopped \
  -e MAX_CLK="${MAX_CLK:-2400}" -e MIN_CLK="${MIN_CLK:-1400}" \
  -e GPU_HI="${GPU_HI:-86}" -e ZONE_HI="${ZONE_HI:-90}" \
  -e GPU_LO="${GPU_LO:-80}" -e ZONE_LO="${ZONE_LO:-84}" \
  -e STEP="${STEP:-100}" -e INTERVAL="${INTERVAL:-5}" \
  -v "$DIR":/app -v /sys:/sys --entrypoint bash "$IMG" /app/gpu-thermal-governor.sh
echo "governor deployed; follow with: docker logs -f gpu-governor"
