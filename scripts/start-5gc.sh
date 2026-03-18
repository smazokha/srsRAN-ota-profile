#!/bin/bash
#
# start-5gc.sh - Start Open5GS 5G Core services
#

set -euo pipefail

echo "Starting Open5GS 5G Core Network..."

# Ensure TUN devices are up
if ! ip link show ogstun > /dev/null 2>&1; then
    ip tuntap add name ogstun mode tun
    ip addr add 10.45.0.1/16 dev ogstun
    ip link set ogstun up
fi

if ! ip link show ogstun2 > /dev/null 2>&1; then
    ip tuntap add name ogstun2 mode tun
    ip addr add 10.46.0.1/16 dev ogstun2
    ip link set ogstun2 up
fi

# Ensure NAT rules
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -C POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -t nat -C POSTROUTING -s 10.46.0.0/16 ! -o ogstun2 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.46.0.0/16 ! -o ogstun2 -j MASQUERADE

# Start MongoDB
systemctl start mongod 2>/dev/null || systemctl start mongodb 2>/dev/null || true

# Start all Open5GS NFs in proper order
OPEN5GS_SERVICES=(
    "open5gs-nrfd"     # NRF - NF Repository Function
    "open5gs-scpd"     # SCP - Service Communication Proxy
    "open5gs-ausfd"    # AUSF - Authentication Server Function
    "open5gs-udmd"     # UDM - Unified Data Management
    "open5gs-udrd"     # UDR - Unified Data Repository
    "open5gs-pcfd"     # PCF - Policy Control Function
    "open5gs-bsfd"     # BSF - Binding Support Function
    "open5gs-nssfd"    # NSSF - Network Slice Selection Function
    "open5gs-amfd"     # AMF - Access and Mobility Management Function
    "open5gs-smfd"     # SMF - Session Management Function
    "open5gs-upfd"     # UPF - User Plane Function
)

for svc in "${OPEN5GS_SERVICES[@]}"; do
    echo "  Starting ${svc}..."
    systemctl restart "${svc}" 2>/dev/null || true
    sleep 1
done

# Verify services are running
echo ""
echo "Open5GS service status:"
for svc in "${OPEN5GS_SERVICES[@]}"; do
    STATUS=$(systemctl is-active "${svc}" 2>/dev/null || echo "not found")
    printf "  %-25s %s\n" "${svc}" "${STATUS}"
done

echo ""
echo "5G Core is running."
echo "AMF NGAP listening on: $(ss -tlnp | grep 38412 | awk '{print $4}' || echo 'checking...')"
echo "Logs: /var/log/open5gs/"
echo ""
echo "Start iperf3 server:  iperf3 -s -B 10.45.0.1"
