# Reading the fan on GB10 / ASUS GX10 (and why you cannot)

Short version: **there is no OS-reachable way to read the internal fan RPM on the
GB10 (DGX Spark / ASUS Ascent GX10), and no way to control the fan.** This page
documents the recon that proves it, so you do not have to repeat it, and sketches
the only remaining route (reverse-engineering the EC firmware) for the curious.

The fan is owned entirely by the board's embedded controller (EC). Its tachometer
never reaches the Grace SoC through any interface the OS can see.

## What was checked (ASUS GX10, BIOS GX10DGX.0104)

Run `recon-fan.sh` (needs root; reads ACPI tables, device tree, SCMI debugfs, I2C,
hwmon). Results on a GX10:

| channel | command | result |
|---|---|---|
| NVML | `nvidia-smi --query-gpu=fan.speed --format=csv` | `N/A` |
| hwmon | `cat /sys/class/hwmon/hwmon*/name` | `acpitz nvme mlx5 mlx5 mlx5 mlx5 mt7925_phy0` -- temps only, no fan |
| ACPI | `acpidump -b && iasl -d *.dat && grep -iE 'fan\|_FST\|tach' *.dsl` | no Fan device, no `_FST`/`_FIF`/tach method |
| device tree | `find /proc/device-tree -iname '*fan*' -o -iname '*pwm*' -o -iname '*tach*'` | nothing |
| SCMI | `ls /sys/kernel/debug/scmi/ ; ls /sys/bus/scmi/devices/` | bus registered but **empty**: no devices, no DT node, no sensor protocol |
| I2C | `i2cdetect -l` | 6 NVIDIA GPU-side adapters, no exposed board EC |
| lm-sensors | `sensors` | temps only; **no `acpi_fan`** on this unit |

Note: some forum reports mention an `acpi_fan` `fan1` value via `sensors` on certain
units/kernels, but it reads a useless coarse value (often stuck at "2 RPM"). It was
not present at all on the GX10 tested here.

`nvidia-smi -pl` (power cap) is also `N/A`, so the GPU **clock cap is the only
thermal lever** -- which is what the rest of this toolkit uses.

## Why

GB10 is aarch64. There is no classic x86 ACPI EC (port 0x62/0x66) and no BMC/IPMI.
The platform EC (an MCU on the ASUS board) handles the fan curve autonomously from
temperature and exposes neither RPM nor a control interface to the SoC. NVIDIA
staff have stated outright that fan speed cannot be controlled from the OS.

## The only remaining route: reverse-engineer the EC firmware

This is a hardware/firmware project with uncertain payoff. Order of increasing effort:

1. **Pull the vendor firmware package** (ASUS GX10 BIOS/EC update, if published) and
   extract the EC image from it. Pure software, no hardware, no brick risk. This is
   the tractable entry point.
2. **Identify the EC chip** on the board (likely ITE IT89xx, Nuvoton NPCX, or ENE --
   these carry the fan-tach inputs).
3. **Disassemble the EC image in Ghidra.** Find the tach register and, critically,
   whether the EC accepts a **host command** (eSPI / LPC / I2C / SMBus) to report
   RPM. On aarch64 the host-to-EC link is undocumented, so this is the uncertain part.
4. If a host-readable command exists, write a small kernel driver or userspace tool
   to poll it. If the tach is purely internal with no host command, it is
   unreachable without physically tapping the EC.

## Recommendation: do not bother

- It is a days-to-weeks effort for a value that is, at best, a read-only number.
- You cannot control the fan regardless, so RPM changes no mitigation.
- The **board (acpitz) temperature is the signal that actually matters**: it tracks
  the OCP/thermal trip far better than fan RPM would, and the governor in this
  toolkit already acts on it.

Read temps, govern the clock, and (if you need more headroom) cool the box
physically. Fan RPM is not the missing piece.
