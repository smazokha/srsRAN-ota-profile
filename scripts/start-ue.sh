#!/bin/bash
#
# start-ue.sh - Attach the Quectel RM520N modem to the srsRAN 5G cell
#
# Run this on each NUC node after the gNodeB is transmitting.
# The script configures the modem, triggers attachment, and brings
# up the data connection so that iperf3 can run over 5G.
#

set -euo pipefail

UE_INDEX=$(cat /var/run/ue_index 2>/dev/null || echo "1")

echo "======================================"
echo "  Starting UE #${UE_INDEX}"
echo "======================================"

# ---------------------------------------------------------------
# Detect AT port
# ---------------------------------------------------------------
AT_PORT=""
for port in /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0 /dev/ttyUSB3; do
    if [ -e "${port}" ]; then
        RESPONSE=$(echo -e "ATI\r" | timeout 3 socat - "${port},b115200,raw,echo=0" 2>/dev/null || true)
        if echo "${RESPONSE}" | grep -qi "quectel\|RM520\|OK"; then
            AT_PORT="${port}"
            break
        fi
    fi
done

if [ -z "${AT_PORT}" ]; then
    echo "ERROR: Could not find Quectel AT command port"
    echo "Available serial ports:"
    ls -la /dev/ttyUSB* 2>/dev/null || echo "  None"
    exit 1
fi

echo "AT port: ${AT_PORT}"

# Helper function to send AT commands
at_cmd() {
    local cmd="$1"
    local wait="${2:-2}"
    echo "  > ${cmd}"
    RESULT=$(echo -e "${cmd}\r" | timeout $((wait + 2)) socat - "${AT_PORT},b115200,raw,echo=0" 2>/dev/null || true)
    echo "  ${RESULT}" | head -5
    sleep "${wait}"
}

# ---------------------------------------------------------------
# Configure modem for 5G SA
# ---------------------------------------------------------------
echo ""
echo "[1/4] Configuring modem for 5G SA mode..."

# Reset to known state
at_cmd "AT+CFUN=0" 3

# Set 5G NR SA only
at_cmd 'AT+QNWPREFCFG="mode_pref",NR5G' 1

# Set NR band n78
at_cmd 'AT+QNWPREFCFG="nr5g_band",78' 1

# Configure APN
at_cmd 'AT+CGDCONT=1,"IPV4V6","internet"' 1

# Set PLMN manually (998/98 = POWDER test network)
at_cmd 'AT+COPS=1,2,"99898",12' 1

# Power on radio
at_cmd "AT+CFUN=1" 5

# ---------------------------------------------------------------
# Wait for registration
# ---------------------------------------------------------------
echo ""
echo "[2/4] Waiting for 5G NR registration..."

REGISTERED=0
for attempt in $(seq 1 30); do
    REG_STATUS=$(echo -e "AT+C5GREG?\r" | timeout 3 socat - "${AT_PORT},b115200,raw,echo=0" 2>/dev/null || true)
    if echo "${REG_STATUS}" | grep -qE "\+C5GREG: [0-9],1|\+C5GREG: [0-9],5"; then
        echo "  Registered to 5G NR network! (attempt ${attempt})"
        REGISTERED=1
        break
    fi
    echo "  Waiting... (${attempt}/30) - ${REG_STATUS}"
    sleep 3
done

if [ ${REGISTERED} -eq 0 ]; then
    echo "WARNING: Not registered after 90s. Check gNodeB status."
    echo "Current registration status:"
    at_cmd "AT+C5GREG?" 1
    at_cmd "AT+COPS?" 1
    at_cmd 'AT+QENG="servingcell"' 1
fi

# ---------------------------------------------------------------
# Bring up data connection
# ---------------------------------------------------------------
echo ""
echo "[3/4] Bringing up data connection..."

# Try QMI first
QMI_DEV=""
for dev in /dev/cdc-wdm0 /dev/cdc-wdm1; do
    if [ -e "${dev}" ]; then
        QMI_DEV="${dev}"
        break
    fi
done

WWAN_IF=""
for iface in wwan0 wwan0mbim0 rmnet_data0; do
    if ip link show "${iface}" > /dev/null 2>&1; then
        WWAN_IF="${iface}"
        break
    fi
done

if [ -n "${QMI_DEV}" ]; then
    echo "  Using QMI on ${QMI_DEV}..."

    # Set raw IP mode
    if [ -n "${WWAN_IF}" ]; then
        ip link set "${WWAN_IF}" down 2>/dev/null || true
        echo Y > /sys/class/net/${WWAN_IF}/qmi/raw_ip 2>/dev/null || true
    fi

    # Start network connection via QMI
    qmicli -d "${QMI_DEV}" --wds-start-network="ip-type=4,apn=internet" --client-no-release-cid || true
    sleep 2

    if [ -n "${WWAN_IF}" ]; then
        ip link set "${WWAN_IF}" up
        # Try to get IP via DHCP or QMI
        dhclient "${WWAN_IF}" 2>/dev/null || \
        udhcpc -i "${WWAN_IF}" 2>/dev/null || true
    fi
else
    echo "  QMI device not found, using AT commands for data connection..."
    at_cmd "AT+QIACT=1" 5
fi

# ---------------------------------------------------------------
# Verify connectivity
# ---------------------------------------------------------------
echo ""
echo "[4/4] Verifying data connection..."

sleep 3

# Show assigned IP
if [ -n "${WWAN_IF}" ]; then
    UE_IP=$(ip -4 addr show "${WWAN_IF}" 2>/dev/null | grep -oP 'inet \K[^/]+' || echo "none")
    echo "  UE IP on ${WWAN_IF}: ${UE_IP}"
else
    # Get IP from modem
    at_cmd "AT+CGPADDR" 1
    UE_IP="unknown"
fi

# Try ping to UPF/core
if [ "${UE_IP}" != "none" ] && [ "${UE_IP}" != "unknown" ]; then
    echo "  Pinging 10.45.0.1 (UPF gateway)..."
    ping -c 3 -W 2 -I "${WWAN_IF}" 10.45.0.1 2>/dev/null && echo "  Ping successful!" || echo "  Ping failed (may need routing)"
fi

echo ""
echo "======================================"
echo "  UE #${UE_INDEX} startup complete!"
echo "======================================"
echo ""
echo "Modem status:  modem-status"
echo "iperf3 test:   iperf3 -c 10.45.0.1 ${WWAN_IF:+-B ${UE_IP}}"
echo "AT commands:   at-cmd 'AT+CSQ' ${AT_PORT}"
