#!/bin/bash
#
# start-ue.sh - Launch srsUE for 5G NR SA attachment
#
# Run this on each NUC node after the gNodeB is transmitting.
# srsUE will scan for the cell on band n78, register with Open5GS,
# and bring up the tun_srsue tunnel interface for data traffic.
#

set -euo pipefail

UE_INDEX=$(cat /var/run/ue_index 2>/dev/null || echo "1")
UE_CONF="/etc/srsran/ue.conf"
UE_LOG="/tmp/srsue.log"

echo "======================================"
echo "  Starting srsUE - NUC #${UE_INDEX}"
echo "======================================"

# ---------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------
if ! command -v srsue &>/dev/null; then
    echo "ERROR: srsue not found. Run setup-ue.sh first."
    exit 1
fi

if [ ! -f "${UE_CONF}" ]; then
    echo "ERROR: UE config not found at ${UE_CONF}. Run setup-ue.sh first."
    exit 1
fi

echo "IMSI: $(grep '^imsi' ${UE_CONF} | awk '{print $3}')"
echo "Band: $(grep '^bands' ${UE_CONF} | awk '{print $3}')"
echo "ARFCN: $(grep '^dl_nr_arfcn' ${UE_CONF} | awk '{print $3}')"
echo ""

# Kill any existing srsUE instance
if pgrep -x srsue > /dev/null; then
    echo "Stopping existing srsUE instance..."
    pkill -x srsue || true
    sleep 2
fi

# Remove stale TUN interface if present
if ip link show tun_srsue > /dev/null 2>&1; then
    echo "Removing stale tun_srsue interface..."
    ip link delete tun_srsue 2>/dev/null || true
fi

# Clear old log
> "${UE_LOG}"

# ---------------------------------------------------------------
# Launch srsUE
# ---------------------------------------------------------------
echo "Launching srsUE..."
echo "Log: ${UE_LOG}"
echo ""
echo "Watch for:"
echo "  'Found Cell'              - B210 scanning, cell detected"
echo "  'RRC NR connected'        - Radio connected to gNodeB"
echo "  'PDU Session Established' - Data plane up"
echo "  tun_srsue IP assigned     - Ready for iperf3"
echo ""
echo "--------------------------------------"

# Run srsUE in foreground so output is visible
# It will create tun_srsue and print connection milestones to stdout
sudo srsue "${UE_CONF}"
