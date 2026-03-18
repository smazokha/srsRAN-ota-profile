#!/bin/bash
#
# setup-gnb-core.sh - Bootstrap script for the gNodeB + 5GC node
#
# This script is executed automatically by Emulab at instantiation.
# It installs Open5GS, builds srsRAN Project from source, configures
# networking, and provisions test subscribers.
#
# Usage: setup-gnb-core.sh <srsran_commit> <nr_band> <dl_arfcn> <channel_bw_mhz> [dl_freq_center_mhz]
#

set -euo pipefail
exec > >(tee -a /var/log/startup-gnb.log) 2>&1

SRSRAN_COMMIT="${1:-main}"
NR_BAND="${2:-n78}"
DL_ARFCN="${3:-640000}"
CHANNEL_BW="${4:-20}"
DL_FREQ_CENTER="${5:-3590.0}"

REPO_DIR="/local/repository"
CONFIG_DIR="${REPO_DIR}/config"
SRSRAN_SRC="/opt/srsRAN_Project"
SRSRAN_BUILD="/opt/srsRAN_Project/build"

echo "======================================"
echo "  srsRAN 5G NR - gNodeB + 5GC Setup"
echo "======================================"
echo "srsRAN commit:  ${SRSRAN_COMMIT}"
echo "NR Band:        ${NR_BAND}"
echo "DL ARFCN:       ${DL_ARFCN}"
echo "Channel BW:     ${CHANNEL_BW} MHz"
echo "DL Freq Center: ${DL_FREQ_CENTER} MHz"
echo ""

# ---------------------------------------------------------------
# Determine IP addresses
# ---------------------------------------------------------------
# The gNB node's primary interface IP (for AMF / gNB N2/N3)
GNB_IP=$(hostname -I | awk '{print $1}')
AMF_IP="127.0.0.5"
UPF_IP="127.0.0.7"

# Auto-detect X310 address from UHD
# In the POWDER OTA Lab, the X310 is connected via 10GbE to the compute node.
# uhd_find_devices will report its IP address.
echo "Detecting X310 USRP..."
X310_ADDR=""
UHD_OUTPUT=$(uhd_find_devices --args="type=x300" 2>/dev/null || true)
if echo "${UHD_OUTPUT}" | grep -q "addr="; then
    X310_ADDR=$(echo "${UHD_OUTPUT}" | grep -oP 'addr=\K[0-9.]+' | head -1)
    echo "  Auto-detected X310 at: ${X310_ADDR}"
fi

# Fallback to common POWDER OTA lab addresses
if [ -z "${X310_ADDR}" ]; then
    # Try common addresses used in the OTA lab
    for CANDIDATE in 192.168.40.2 10.40.1.2 10.10.1.2; do
        if ping -c 1 -W 2 "${CANDIDATE}" > /dev/null 2>&1; then
            X310_ADDR="${CANDIDATE}"
            echo "  Found X310 at fallback address: ${X310_ADDR}"
            break
        fi
    done
fi

if [ -z "${X310_ADDR}" ]; then
    X310_ADDR="192.168.40.2"
    echo "  WARNING: Could not auto-detect X310. Using default: ${X310_ADDR}"
    echo "  Run 'uhd_find_devices --args=type=x300' after boot to find the actual address."
fi

echo ""
echo "gNB IP:  ${GNB_IP}"
echo "AMF IP:  ${AMF_IP}"
echo "UPF IP:  ${UPF_IP}"
echo "X310:    ${X310_ADDR}"
echo ""

# ---------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------
echo "[1/7] Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
    build-essential cmake make gcc g++ pkg-config \
    libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev \
    libgtest-dev libzmq3-dev libboost-all-dev \
    libuhd-dev uhd-host \
    git curl wget net-tools iperf3 \
    python3 python3-pip python3-setuptools \
    mongodb-org || apt-get install -y -qq mongodb \
    gnupg software-properties-common \
    libconfig++-dev libtool autoconf \
    tcpdump wireshark-common tshark

# ---------------------------------------------------------------
# 2. Install UHD and download FPGA images
# ---------------------------------------------------------------
echo "[2/7] Setting up UHD for X310..."
uhd_images_downloader || true

# Verify X310 connectivity (non-fatal if not yet available)
uhd_find_devices --args="type=x300" || echo "WARNING: X310 not found yet (may need network config)"

# ---------------------------------------------------------------
# 3. Install Open5GS
# ---------------------------------------------------------------
echo "[3/7] Installing Open5GS 5G Core..."

# Add Open5GS repository
apt-get install -y -qq gnupg
curl -fsSL https://download.opensuse.org/repositories/home:/acetcom:/open5gs:/latest/xUbuntu_22.04/Release.key | \
    gpg --dearmor -o /usr/share/keyrings/open5gs-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/open5gs-archive-keyring.gpg] https://download.opensuse.org/repositories/home:/acetcom:/open5gs:/latest/xUbuntu_22.04/ ./" | \
    tee /etc/apt/sources.list.d/open5gs.list

apt-get update -qq
apt-get install -y -qq open5gs

# ---------------------------------------------------------------
# 4. Configure Open5GS
# ---------------------------------------------------------------
echo "[4/7] Configuring Open5GS..."

# Create TUN device for UPF
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

# Enable IP forwarding and NAT
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.46.0.0/16 ! -o ogstun2 -j MASQUERADE

# Make persistent
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Deploy AMF config (update NGAP bind address)
cp ${CONFIG_DIR}/open5gs-amf.yaml /etc/open5gs/amf.yaml
sed -i "s|__AMF_ADDR__|${AMF_IP}|g" /etc/open5gs/amf.yaml

# Deploy UPF config
cp ${CONFIG_DIR}/open5gs-upf.yaml /etc/open5gs/upf.yaml
sed -i "s|__UPF_ADDR__|${UPF_IP}|g" /etc/open5gs/upf.yaml

# Deploy SMF config
cp ${CONFIG_DIR}/open5gs-smf.yaml /etc/open5gs/smf.yaml

# ---------------------------------------------------------------
# 5. Provision test subscribers
# ---------------------------------------------------------------
echo "[5/7] Provisioning test subscribers in Open5GS..."

# Wait for MongoDB to be ready
systemctl enable mongod || systemctl enable mongodb || true
systemctl start mongod || systemctl start mongodb || true
sleep 5

# Use open5gs-dbctl or direct MongoDB insertion
if command -v open5gs-dbctl &> /dev/null; then
    while IFS=',' read -r imsi k opc apn sst sd; do
        [[ "$imsi" =~ ^#.*$ ]] && continue
        [[ -z "$imsi" ]] && continue
        echo "  Adding subscriber: IMSI=${imsi}"
        open5gs-dbctl add "${imsi}" "${k}" "${opc}" || true
        open5gs-dbctl type "${imsi}" 1 || true
    done < "${CONFIG_DIR}/subscribers.csv"
else
    # Fallback: use mongosh / mongo to insert subscribers directly
    while IFS=',' read -r imsi k opc apn sst sd; do
        [[ "$imsi" =~ ^#.*$ ]] && continue
        [[ -z "$imsi" ]] && continue
        echo "  Adding subscriber: IMSI=${imsi}"
        MONGO_CMD=$(command -v mongosh || command -v mongo)
        ${MONGO_CMD} --quiet open5gs --eval "
        db.subscribers.updateOne(
            { 'imsi': '${imsi}' },
            { \$set: {
                'imsi': '${imsi}',
                'msisdn': [],
                'imeisv': [],
                'mme_host': [],
                'mme_realm': [],
                'purge_flag': [],
                'security': {
                    'k': '${k}',
                    'amf': '8000',
                    'op_type': 2,
                    'op_value': '${opc}',
                    'op': null
                },
                'ambr': {
                    'downlink': { 'value': 1, 'unit': 3 },
                    'uplink': { 'value': 1, 'unit': 3 }
                },
                'slice': [{
                    'sst': ${sst},
                    'default_indicator': true,
                    'session': [{
                        'name': '${apn}',
                        'type': 3,
                        'pcc_rule': [],
                        'ambr': {
                            'downlink': { 'value': 1, 'unit': 3 },
                            'uplink': { 'value': 1, 'unit': 3 }
                        },
                        'qos': {
                            'index': 9,
                            'arp': {
                                'priority_level': 8,
                                'pre_emption_capability': 1,
                                'pre_emption_vulnerability': 1
                            }
                        }
                    }]
                }],
                'schema_version': 1,
                '__v': 0
            }},
            { upsert: true }
        );" || true
    done < "${CONFIG_DIR}/subscribers.csv"
fi

# ---------------------------------------------------------------
# 6. Build srsRAN Project
# ---------------------------------------------------------------
echo "[6/7] Building srsRAN Project (gNodeB)..."

cd /opt
if [ ! -d "srsRAN_Project" ]; then
    git clone https://github.com/srsran/srsRAN_Project.git
fi

cd srsRAN_Project
git fetch --all
git checkout "${SRSRAN_COMMIT}"

mkdir -p build && cd build
cmake .. -DENABLE_EXPORT=ON -DENABLE_UHD=ON -DAUTO_DETECT_ISA=ON
make -j$(nproc)
make install
ldconfig

# ---------------------------------------------------------------
# 7. Prepare gNodeB configuration
# ---------------------------------------------------------------
echo "[7/7] Generating gNodeB configuration..."

GNB_CONFIG="/etc/srsran/gnb.yml"
mkdir -p /etc/srsran

cp ${CONFIG_DIR}/gnb.yml ${GNB_CONFIG}
sed -i "s|__AMF_ADDR__|${AMF_IP}|g"      ${GNB_CONFIG}
sed -i "s|__GNB_ADDR__|${GNB_IP}|g"      ${GNB_CONFIG}
sed -i "s|__X310_ADDR__|${X310_ADDR}|g"  ${GNB_CONFIG}
sed -i "s|__DL_ARFCN__|${DL_ARFCN}|g"    ${GNB_CONFIG}
sed -i "s|__NR_BAND__|${NR_BAND}|g"      ${GNB_CONFIG}
sed -i "s|__CHANNEL_BW__|${CHANNEL_BW}|g" ${GNB_CONFIG}

# Install convenience scripts
chmod +x ${REPO_DIR}/scripts/start-5gc.sh
chmod +x ${REPO_DIR}/scripts/start-gnb.sh
chmod +x ${REPO_DIR}/scripts/stop-all.sh

echo ""
echo "======================================"
echo "  Setup complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  1. Start 5GC:    sudo /local/repository/scripts/start-5gc.sh"
echo "  2. Start gNodeB:  sudo /local/repository/scripts/start-gnb.sh"
echo "  3. Start UEs on each NUC"
echo "  4. Run iperf3 tests"
echo ""
echo "Configuration:"
echo "  gNB config:  ${GNB_CONFIG}"
echo "  Open5GS dir: /etc/open5gs/"
echo "  Logs:        /var/log/open5gs/ and /tmp/gnb.log"
