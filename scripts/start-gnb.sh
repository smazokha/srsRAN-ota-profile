#!/bin/bash
#
# start-gnb.sh - Start the srsRAN Project gNodeB
#
# Prerequisites: 5GC must be running (start-5gc.sh)
#

set -euo pipefail

GNB_CONFIG="/etc/srsran/gnb.yml"
GNB_BIN="/opt/srsRAN_Project/build/apps/gnb/gnb"

# Fallback to installed location
if [ ! -f "${GNB_BIN}" ]; then
    GNB_BIN=$(which gnb 2>/dev/null || echo "/usr/local/bin/gnb")
fi

if [ ! -f "${GNB_BIN}" ]; then
    echo "ERROR: gnb binary not found. Was srsRAN built successfully?"
    exit 1
fi

if [ ! -f "${GNB_CONFIG}" ]; then
    echo "ERROR: gNB config not found at ${GNB_CONFIG}"
    exit 1
fi

echo "======================================"
echo "  Starting srsRAN gNodeB"
echo "======================================"
echo "Binary: ${GNB_BIN}"
echo "Config: ${GNB_CONFIG}"
echo ""

# Check that AMF is reachable
AMF_ADDR=$(grep "addr:" ${GNB_CONFIG} | head -1 | awk '{print $2}')
echo "Checking AMF at ${AMF_ADDR}..."
if ss -tlnp | grep -q 38412; then
    echo "  AMF NGAP port (38412) is listening. Good."
else
    echo "  WARNING: AMF may not be running. Start 5GC first with: sudo /local/repository/scripts/start-5gc.sh"
fi

# Check X310 reachability
X310_ADDR=$(grep "device_args:" ${GNB_CONFIG} | grep -oP 'addr=\K[^,]+')
echo "Checking X310 at ${X310_ADDR}..."
if ping -c 1 -W 2 "${X310_ADDR}" > /dev/null 2>&1; then
    echo "  X310 reachable. Good."
else
    echo "  WARNING: X310 at ${X310_ADDR} not reachable. Check network config."
fi

echo ""
echo "Starting gNodeB... (Ctrl+C to stop)"
echo "Log file: /tmp/gnb.log"
echo ""

# Set real-time scheduling priority for better performance
ulimit -r unlimited 2>/dev/null || true

# Start gNodeB
sudo ${GNB_BIN} -c ${GNB_CONFIG}
