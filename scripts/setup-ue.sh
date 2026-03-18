#!/bin/bash
#
# setup-ue.sh - Bootstrap script for NUC nodes with Quectel RM520N modems
#
# This script is executed automatically by Emulab at instantiation.
# It installs modem management tools, configures the Quectel RM520N,
# and prepares the UE for attachment to the srsRAN 5G cell.
#
# Usage: setup-ue.sh <ue_index>
#

set -euo pipefail
exec > >(tee -a /var/log/startup-ue.log) 2>&1

UE_INDEX="${1:-1}"

REPO_DIR="/local/repository"

echo "======================================"
echo "  UE Node Setup - NUC #${UE_INDEX}"
echo "======================================"

# ---------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------
echo "[1/5] Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
    build-essential cmake \
    libqmi-utils libmbim-utils modemmanager \
    net-tools iperf3 curl wget \
    python3 python3-pip python3-serial \
    minicom picocom socat \
    tcpdump iproute2 usbutils \
    pciutils linux-tools-common

# ---------------------------------------------------------------
# 2. Detect Quectel modem
# ---------------------------------------------------------------
echo "[2/5] Detecting Quectel RM520N modem..."

# Wait for modem USB device to appear
MODEM_WAIT=0
while [ ${MODEM_WAIT} -lt 30 ]; do
    if lsusb | grep -qi "quectel"; then
        echo "  Quectel modem detected via USB"
        break
    fi
    echo "  Waiting for modem... (${MODEM_WAIT}s)"
    sleep 2
    MODEM_WAIT=$((MODEM_WAIT + 2))
done

lsusb | grep -i quectel || echo "WARNING: Quectel modem not detected via lsusb"

# Find the modem AT command port
sleep 3
AT_PORT=""
for port in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
    if [ -e "${port}" ]; then
        # Send ATI to check if this is the AT port
        RESPONSE=$(echo -e "ATI\r" | timeout 3 socat - "${port},b115200,raw,echo=0" 2>/dev/null || true)
        if echo "${RESPONSE}" | grep -qi "quectel\|RM520"; then
            AT_PORT="${port}"
            echo "  AT command port: ${AT_PORT}"
            break
        fi
    fi
done

# Also check for QMI/MBIM device
QMI_DEV=""
for dev in /dev/cdc-wdm0 /dev/cdc-wdm1; do
    if [ -e "${dev}" ]; then
        QMI_DEV="${dev}"
        echo "  QMI device: ${QMI_DEV}"
        break
    fi
done

# ---------------------------------------------------------------
# 3. Configure ModemManager
# ---------------------------------------------------------------
echo "[3/5] Configuring ModemManager..."

# Stop ModemManager initially (we may want direct AT access)
systemctl stop ModemManager || true
systemctl disable ModemManager || true

# ---------------------------------------------------------------
# 4. Create AT command helper scripts
# ---------------------------------------------------------------
echo "[4/5] Creating modem helper scripts..."

mkdir -p /usr/local/bin

# AT command sender
cat > /usr/local/bin/at-cmd <<'ATEOF'
#!/bin/bash
# Send AT command to Quectel modem
# Usage: at-cmd "AT+COPS?" [port]
CMD="${1:-ATI}"
PORT="${2:-/dev/ttyUSB2}"
echo -e "${CMD}\r" | timeout 5 socat - "${PORT},b115200,raw,echo=0" 2>/dev/null
ATEOF
chmod +x /usr/local/bin/at-cmd

# Modem status checker
cat > /usr/local/bin/modem-status <<'MSEOF'
#!/bin/bash
# Check Quectel RM520N modem status
PORT="${1:-/dev/ttyUSB2}"
echo "=== Modem Info ==="
at-cmd "ATI" "${PORT}"
echo ""
echo "=== Signal Quality ==="
at-cmd "AT+CSQ" "${PORT}"
echo ""
echo "=== Registration Status ==="
at-cmd "AT+C5GREG?" "${PORT}"
echo ""
echo "=== Serving Cell ==="
at-cmd 'AT+QENG="servingcell"' "${PORT}"
echo ""
echo "=== Network Operator ==="
at-cmd "AT+COPS?" "${PORT}"
echo ""
echo "=== PDP Context ==="
at-cmd "AT+CGDCONT?" "${PORT}"
echo ""
echo "=== IP Address ==="
at-cmd "AT+CGPADDR" "${PORT}"
MSEOF
chmod +x /usr/local/bin/modem-status

# ---------------------------------------------------------------
# 5. Pre-configure modem for srsRAN 5G SA cell
# ---------------------------------------------------------------
echo "[5/5] Pre-configuring modem for 5G SA..."

# Determine AT port (use detected or fallback)
AT="${AT_PORT:-/dev/ttyUSB2}"

if [ -e "${AT}" ]; then
    # Set modem to 5G SA only mode (NR standalone)
    echo "  Setting 5G NR SA mode..."
    at-cmd 'AT+QNWPREFCFG="mode_pref",NR5G' "${AT}" || true
    sleep 1

    # Set band to n78
    echo "  Configuring NR band n78..."
    at-cmd 'AT+QNWPREFCFG="nr5g_band",78' "${AT}" || true
    sleep 1

    # Configure test PLMN (MCC=998, MNC=98 = POWDER test network)
    echo "  Setting PLMN to 99898..."
    at-cmd 'AT+COPS=1,2,"99898",12' "${AT}" || true
    sleep 1

    # Configure APN
    echo "  Setting APN..."
    at-cmd 'AT+CGDCONT=1,"IPV4V6","internet"' "${AT}" || true
    sleep 1

    echo "  Modem pre-configuration complete."
else
    echo "  WARNING: AT port not found. Manual modem config will be needed."
fi

# Install convenience scripts
chmod +x ${REPO_DIR}/scripts/start-ue.sh 2>/dev/null || true

# Save UE index for runtime scripts
echo "${UE_INDEX}" > /var/run/ue_index

echo ""
echo "======================================"
echo "  NUC #${UE_INDEX} setup complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  1. Ensure gNodeB + 5GC are running on the gNB node"
echo "  2. Start UE:  sudo /local/repository/scripts/start-ue.sh"
echo "  3. Check:     modem-status"
echo "  4. iperf3:    iperf3 -c <gnb_ip> -B <ue_ip>"
