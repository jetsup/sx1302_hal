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
