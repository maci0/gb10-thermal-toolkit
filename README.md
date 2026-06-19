# GB10 Thermal Toolkit

Thermal mitigation tooling for NVIDIA GB10 "DGX Spark"-class mini systems
(NVIDIA Founders, **ASUS Ascent GX10**, MSI EdgeXpert, etc.). These boxes hard
power-off under sustained GPU load. The GPU clock cap is the only effective
software lever, so this toolkit caps it, and a small governor adjusts the cap in a
closed loop from temperature.

## The problem

Many GB10 units hard *power off* (not reboot) within seconds to minutes of sustained
heavy GPU load (vLLM, long-context inference, GPU stress). Two overlapping causes are
reported:

- **Over-current protection (OCP):** the unit trips at modest temperature and power
  (60-70 C, ~85-90 W). `nvidia-smi -pl` reads N/A, so there is no software power cap.
- **Board / Grace-CPU thermal cutoff:** the **board (acpitz) sensors run ~10 C hotter
  than the GPU die**, hitting ~95-96 C right before the cutoff while the GPU still
  reads ~84-89 C.

NVIDIA cannot reproduce it generally and treats failing units as hardware defects
(RMA; ASUS units route to ASUS RMA). There is no firmware fix that eliminates it.

What you **cannot** do on GB10:

- No OS fan control (the embedded controller owns the fan curve; NVIDIA confirmed).
- No reliable fan-RPM read (no `hwmon` fan input, no PWM, no BMC/IPMI; the lone
  `acpi_fan` value is coarse/stuck).
- No power cap (`nvidia-smi -pl` is N/A).

What you **can** do: cap the GPU graphics clock with `nvidia-smi -lgc`. That is the
single lever this toolkit uses.

## What is in here

| file | what it does |
|---|---|
| `gpu-thermal-governor.sh` | Closed-loop governor. Watches GPU temp **and the hottest board/acpitz zone**, steps the clock cap down when hot and back up when cool (hysteresis). The clock cap is the only thermal actuator on GB10. |
| `gpu-thermal-log.sh` | Logs `util / gpu temp / power / sm clock / board zones` to the journal once a minute, but only when the GPU is active (util above a threshold). |
| `systemd/nvidia-gb10-clock-cap.service` | Static clock cap applied at boot (a safe floor before the governor takes over). |
| `systemd/gpu-thermal-log.service` + `.timer` | Run the thermal logger every minute. |
| `deploy-docker.sh` | Deploy the governor as an auto-restarting container (no sudo needed; survives reboot). |

## Key insight: watch the board, not the GPU

The trip is driven by the **board / Grace-CPU** sensor, which runs much hotter than the
GPU die. Capping or governing on GPU temperature alone is not enough: the GPU can read
a comfortable 84 C while the board sits at 95 C, one step from the cutoff. The governor
reacts to whichever is hotter.

## Closed-loop behaviour

The governor floats the clock cap between a floor and ceiling, stepping it to hold both
the GPU and board temperatures inside a safe band. On a marginally-cooled unit under
sustained load it will floor the clock; on a well-cooled unit it will sit near the
ceiling. Sample run on an ASUS GX10 under a vLLM benchmark:

![clock vs temperature](clock-temp-curve.png)

## Install

### Option A: docker (no sudo, survives reboot)

```bash
./deploy-docker.sh        # runs the governor as a --restart=unless-stopped container
```

### Option B: native systemd

```bash
sudo cp gpu-thermal-governor.sh gpu-thermal-log.sh /usr/local/bin/
sudo chmod 755 /usr/local/bin/gpu-thermal-governor.sh /usr/local/bin/gpu-thermal-log.sh
sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nvidia-gb10-clock-cap.service   # static safe cap at boot
sudo systemctl enable --now gpu-thermal-governor.service    # dynamic governor
sudo systemctl enable --now gpu-thermal-log.timer           # periodic thermal log
```

Watch it:

```bash
journalctl -u gpu-thermal-governor -f       # cap changes
journalctl -u gpu-thermal-log.service -f    # periodic thermals
```

## Tuning

Governor knobs (env vars, with defaults):

| var | default | meaning |
|---|---|---|
| `MAX_CLK` | 2400 | ceiling MHz (stock is 3003) |
| `MIN_CLK` | 1400 | floor MHz |
| `GPU_HI` / `GPU_LO` | 86 / 80 | GPU temp step-down / step-up thresholds (C) |
| `ZONE_HI` / `ZONE_LO` | 90 / 84 | board (acpitz) step-down / step-up thresholds (C) |
| `STEP` | 100 | MHz per adjustment |
| `INTERVAL` | 5 | poll seconds |

Reported-working static caps from the community range 2000-2300 MHz (2200 is a common
sweet spot; go lower in a warm room or if your unit still trips). Performance loss for
LLM inference is small because GB10 is memory-bandwidth-bound, not clock-bound.

If your unit still powers off with a 2000 MHz cap, it is likely defective: RMA it.

## Notes

- The clock cap is set with `nvidia-smi -lgc 0,<MHz>` and persists while persistence
  mode is on (`nvidia-smi -pm 1`).
- After an OCP power-off a unit can latch into a stuck low-power state (~14 W, 0% util);
  disconnect power for ~5 minutes to reset the controller.
- Always use the supplied power adapter; others can cause shutdowns.
- The governor process is a few MB, leak-free (scalar-only loop), `timeout`-guarded
  against a hung `nvidia-smi`, and self-restarts cleanly once a day.

## References

- NVIDIA dev forum, shutdown-under-load / RMA threads (the canonical ones):
  - https://forums.developer.nvidia.com/t/to-nvidia-staff-is-this-a-hardware-issue-requiring-repeated-shutdowns-and-rma-under-high-load/362775
  - https://forums.developer.nvidia.com/t/dgx-spark-gb10-reproducibly-hard-powers-off-under-gpu-load-fully-updated-zero-crash-capture/373251
  - ASUS GX10 under vLLM: https://forums.developer.nvidia.com/t/title-asus-ascent-gx10-gb10-hard-power-off-unclean-reboot-under-vllm-gpt-oss-120b-long-context/359785
- No OS fan control: https://forums.developer.nvidia.com/t/fan-control-from-the-os/360020
- Clock-cap writeup: https://www.wildpines.ai/blog/your-dgx-spark-is-cooking-itself/
