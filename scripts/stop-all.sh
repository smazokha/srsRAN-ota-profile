#!/bin/bash
#
# stop-all.sh - Stop gNodeB and all Open5GS services
#
# Run on the gNB/core node to cleanly shut everything down.
#

echo "Stopping srsRAN gNodeB..."
pkill -f "gnb" 2>/dev/null || true
sleep 2

echo "Stopping Open5GS services..."
OPEN5GS_SERVICES=(
    "open5gs-upfd"
    "open5gs-smfd"
    "open5gs-amfd"
    "open5gs-nssfd"
    "open5gs-bsfd"
    "open5gs-pcfd"
    "open5gs-udrd"
    "open5gs-udmd"
    "open5gs-ausfd"
    "open5gs-scpd"
    "open5gs-nrfd"
)

for svc in "${OPEN5GS_SERVICES[@]}"; do
    systemctl stop "${svc}" 2>/dev/null || true
done

echo "All services stopped."
