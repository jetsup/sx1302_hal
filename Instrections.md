# Waveshare SX1303 915M LoRaWAN Gateway (B) — Setup & Deployment Guide

This guide documents the permanent configuration, build, and deployment setup for running `sx1302_hal` with a **Waveshare SX1303 915M LoRaWAN Gateway (B)** HAT on a Raspberry Pi (`berry-alpha`).

## Hardware & Environment Summary
* **Gateway Module:** Waveshare SX1303 915M LoRaWAN Gateway (B)
* **Concentrator EUI:** `0x0016c001f15d0a4d`
* **Frequency Plan:** `US915` (`SX1250` SPI)
* **SPI Interface:** `/dev/spidev0.0`
* **GPIO Reset Control:** `pinctrl` (required for Raspberry Pi kernels `6.18+` where legacy `/sys/class/gpio` is deprecated/unavailable)
* **Onboard GPS UART:** `/dev/ttyS0` (`/dev/serial0`)
* **Build Target User:** Dynamic `$(USER)` in `target.cfg`

---

## 1. Repository Configuration (`/opt/Creations/Projects/sx1302_hal`)

### 1.1 Branch Setup
Keep all hardware and OS customizations on a dedicated branch (`waveshare-sx1303-us915`):
```bash
cd /opt/Creations/Projects/sx1302_hal
git checkout -B waveshare-sx1303-us915
```

### 1.2 Dynamic User in `target.cfg`
Configure `target.cfg` so `TARGET_USR` resolves to the active logged-in user (`$(USER)`) and `TARGET_DIR` builds dynamically without hardcoding `pi`:
```makefile
# That file will be included in the Makefiles to configure where to install files on the target

# The IP address of the gateway host on which the files need to be installed
TARGET_IP ?= localhost

# The user to be used by ssh/scp to copy the files on the gateway host (defaults to logged-in user)
TARGET_USR ?= $(USER)

# The directory on the gateway file system to which the files need to be installed
TARGET_DIR ?= /home/$(TARGET_USR)/sx1302_hal/bin
```

### 1.3 Tracked Customizations
Ensure the following files are updated and committed in your repository:
1. **`tools/reset_lgw.sh`:** Uses `pinctrl` to control `GPIO23` (CoreCell reset), `GPIO22` (SX1261 reset), `GPIO18` (CoreCell power enable), and `GPIO13` (CoreCell ADC reset).
2. **`packet_forwarder/global_conf.json.sx1250.US915`:** Configured for `US915` with:
   * `"gateway_ID": "0016c001f15d0a4d"`
   * `"gps_tty_path": "/dev/ttyS0"`
   * Target LoRaWAN Network Server `server_address`, `serv_port_up`, and `serv_port_down`.
3. **`tools/setup_rpi_gps_uart.sh`:** Automates Raspberry Pi UART permissions and serial console disabling.

---

## 2. Raspberry Pi OS & GPS UART Setup (`berry-alpha`)

### 2.1 Boot Firmware Settings (`/boot/firmware/config.txt`)
Ensure UART and SPI are enabled:
```ini
enable_uart=1
dtparam=spi=on
```

### 2.2 Free `/dev/ttyS0` from Serial Console & Set Permissions
Run `tools/setup_rpi_gps_uart.sh` on the Raspberry Pi:
```bash
#!/bin/sh
set -e

sudo systemctl stop serial-getty@ttyS0.service 2>/dev/null || true
sudo systemctl mask serial-getty@ttyS0.service

echo 'KERNEL=="ttyS0", SYMLINK+="serial0", GROUP="dialout", MODE="0660"' | sudo tee /etc/udev/rules.d/99-lora-gps.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=ttyS0

if [ -f /boot/firmware/cmdline.txt ]; then
    sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
    sudo sed -i 's/console=serial0,[0-9]\+ //g' /boot/firmware/cmdline.txt
fi

echo "Done. Reboot if /boot/firmware/cmdline.txt was modified."
```

Reboot the Raspberry Pi if `/boot/firmware/cmdline.txt` was updated:
```bash
sudo reboot
```

### 2.3 Verify GPS NMEA Stream
Confirm `/dev/ttyS0` is owned by `root:dialout` (`0660`) and streaming NMEA sentences:
```bash
ls -l /dev/ttyS0 /dev/serial0
timeout 3 cat /dev/ttyS0
```
> **Note:** When the GPS antenna is indoors, `/dev/ttyS0` will typically acquire valid time (`$GNZDA`) while reporting `V` (invalid position fix) and `PPS: 0` until placed near a window or outdoors with clear sky visibility.

---

## 3. Build, Install, and Run

From the repository root on the Raspberry Pi (`~/sx1302_hal`):
```bash
cd ~/sx1302_hal
make && make install && make install_conf
cp bin/global_conf.json.sx1250.US915 bin/global_conf.json
```

Start the packet forwarder:
```bash
cd ~/sx1302_hal/bin
./lora_pkt_fwd
```

### Startup Verification Checklist
* `INFO: com_type SPI, com_path /dev/spidev0.0, lorawan_public 1, clksrc 0, full_duplex 0`
* `INFO: radio 0 enabled (type SX1250), center frequency 904300000`
* `INFO: gateway MAC address is configured to 0016C001F15D0A4D`
* `INFO: [main] TTY port /dev/ttyS0 open for GPS synchronization`
* `INFO: [main] concentrator started, packet can now be received`
* `INFO: concentrator EUI: 0x0016c001f15d0a4d`

---

## 4. Important Configuration Note
Because `global_conf.json` includes its own `"gateway_conf"` block, `lora_pkt_fwd` prioritizes the `"gateway_conf"` parameters inside `global_conf.json` over `local_conf.json`. Always update `server_address`, `serv_port_up`, and `serv_port_down` inside `global_conf.json` (and sync back to `packet_forwarder/global_conf.json.sx1250.US915`) when changing network servers.