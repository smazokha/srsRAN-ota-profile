#!/bin/bash
# Network buffer and MTU tuning for X310 10GbE interface (from srslte-otalab)

# Increase network buffer sizes for high-throughput SDR streaming
sudo sysctl -w net.core.wmem_max=24862979
sudo sysctl -w net.core.rmem_max=24862979

# Set MTU to 9000 (jumbo frames) on the SDR-facing interface
SDR_IFACE=$(ifconfig | grep -B1 192.168.40.1 | grep -o "^\w*")
if [ -n "$SDR_IFACE" ]; then
    sudo ifconfig $SDR_IFACE mtu 9000
    echo "Set MTU 9000 on $SDR_IFACE"
else
    echo "WARNING: Could not find SDR interface (192.168.40.1)"
fi
