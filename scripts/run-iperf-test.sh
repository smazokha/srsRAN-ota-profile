#!/bin/bash
#
# run-iperf-test.sh - Run iperf3 throughput tests between gNodeB and UEs
#
# Run this on the gNodeB/core node. It will:
#   1. Start iperf3 servers on the UPF TUN interface
#   2. SSH to each NUC and run iperf3 clients
#
# Usage: run-iperf-test.sh [duration_secs] [direction]
#   direction: "dl" (downlink), "ul" (uplink), or "both" (default)
#

DURATION="${1:-10}"
DIRECTION="${2:-both}"
NUM_UES=$(ls /var/run/ue_nodes.txt 2>/dev/null | wc -l || echo 4)

CORE_IP="10.45.0.1"
IPERF_BASE_PORT=5201

echo "======================================"
echo "  iperf3 Throughput Test"
echo "======================================"
echo "Duration:  ${DURATION}s"
echo "Direction: ${DIRECTION}"
echo "Core IP:   ${CORE_IP}"
echo ""

# Start iperf3 server on the core
echo "Starting iperf3 servers..."
for i in $(seq 0 3); do
    PORT=$((IPERF_BASE_PORT + i))
    pkill -f "iperf3.*-p ${PORT}" 2>/dev/null || true
    iperf3 -s -B ${CORE_IP} -p ${PORT} -D
    echo "  Server on port ${PORT}"
done

echo ""
echo "iperf3 servers are running on ${CORE_IP}:${IPERF_BASE_PORT}-$((IPERF_BASE_PORT+3))"
echo ""
echo "To run a test from a UE node:"
echo "  Downlink: iperf3 -c ${CORE_IP} -p ${IPERF_BASE_PORT} -t ${DURATION} -R"
echo "  Uplink:   iperf3 -c ${CORE_IP} -p ${IPERF_BASE_PORT} -t ${DURATION}"
echo ""
echo "To run all UEs simultaneously, SSH to each NUC and use different ports:"
echo "  NUC1: iperf3 -c ${CORE_IP} -p $((IPERF_BASE_PORT))   -t ${DURATION}"
echo "  NUC2: iperf3 -c ${CORE_IP} -p $((IPERF_BASE_PORT+1)) -t ${DURATION}"
echo "  NUC3: iperf3 -c ${CORE_IP} -p $((IPERF_BASE_PORT+2)) -t ${DURATION}"
echo "  NUC4: iperf3 -c ${CORE_IP} -p $((IPERF_BASE_PORT+3)) -t ${DURATION}"
echo ""
echo "Stop servers: pkill iperf3"
