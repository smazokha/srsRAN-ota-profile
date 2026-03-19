#!/bin/bash
#
# setup-ue.sh - Bootstrap script for NUC nodes running srsRAN 4G srsUE
#
# This script is executed automatically by Emulab at instantiation.
# It installs srsRAN 4G (srsUE), configures the B210 SDR, and deploys
# the UE config for 5G NR SA operation against the srsRAN Project gNodeB.
#
# Usage: setup-ue.sh <ue_index> [srsran4g_commit]
#   ue_index:        1-4, determines which IMSI to use (999990000000000 + index - 1)
#   srsran4g_commit: git ref to build (default: master)
#

set -euo pipefail
exec > >(tee -a /var/log/startup-ue.log) 2>&1

UE_INDEX="${1:-1}"
SRSRAN4G_COMMIT="${2:-master}"

REPO_DIR="/local/repository"
CONFIG_DIR="${REPO_DIR}/config"
SRSRAN4G_SRC="/opt/srsRAN_4G"

# IMSI = 99999000000000{index-1}
IMSI="99999000000000$((UE_INDEX - 1))"

echo "======================================"
echo "  srsUE Setup - NUC #${UE_INDEX}"
echo "======================================"
echo "IMSI:           ${IMSI}"
echo "srsRAN 4G ref:  ${SRSRAN4G_COMMIT}"
echo ""

# ---------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------
echo "[1/5] Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
    build-essential cmake make pkg-config \
    libfftw3-dev libmbedtls-dev libconfig++-dev libsctp-dev \
    libboost-program-options-dev libboost-system-dev \
    libboost-thread-dev libboost-filesystem-dev \
    libuhd-dev uhd-host \
    git curl wget \
    net-tools iproute2 iperf3 \
    tcpdump

# ---------------------------------------------------------------
# 2. UHD FPGA images for B210
# ---------------------------------------------------------------
echo "[2/5] Downloading UHD FPGA images for B210..."

# Download only B2xx images (much faster than full download)
uhd_images_downloader -t b2xx || uhd_images_downloader || true

# Verify B210 is visible on USB
echo "Checking for B210 on USB..."
lsusb | grep -i "Ettus\|National Instruments" || echo "  WARNING: B210 not detected on USB yet"

# ---------------------------------------------------------------
# 3. Build srsRAN 4G (provides srsUE)
# ---------------------------------------------------------------
echo "[3/5] Building srsRAN 4G (srsUE)..."

cd /opt
if [ ! -d "srsRAN_4G" ]; then
    git clone https://github.com/srsran/srsRAN_4G.git
fi

cd srsRAN_4G
git fetch --all
git checkout "${SRSRAN4G_COMMIT}"

# Build only srsUE (skip srseNB, srsepc - saves significant build time)
mkdir -p build && cd build
cmake .. \
    -DENABLE_UHD=ON \
    -DENABLE_BLADERF=OFF \
    -DENABLE_SOAPYSDR=OFF \
    -DENABLE_ZEROMQ=OFF \
    -DAUTO_DETECT_ISA=ON

make -j$(nproc) srsue
make install
ldconfig

echo "  srsUE installed: $(which srsue)"

# ---------------------------------------------------------------
# 4. Deploy srsUE configuration
# ---------------------------------------------------------------
echo "[4/5] Deploying srsUE configuration..."

mkdir -p /etc/srsran

# Copy template and substitute IMSI
cp "${CONFIG_DIR}/srsue.conf" /etc/srsran/ue.conf
sed -i "s|__IMSI__|${IMSI}|g" /etc/srsran/ue.conf

echo "  Config deployed: /etc/srsran/ue.conf"
echo "  IMSI set to:     ${IMSI}"

# Verify substitution
if grep -q "__IMSI__" /etc/srsran/ue.conf; then
    echo "  ERROR: IMSI substitution failed"
    exit 1
fi

# ---------------------------------------------------------------
# 5. Final checks
# ---------------------------------------------------------------
echo "[5/5] Verifying setup..."

# Confirm srsue binary
srsue --version 2>/dev/null | head -2 || echo "  WARNING: srsue --version failed"

# Save UE index for runtime scripts
echo "${UE_INDEX}" > /var/run/ue_index

# Mark scripts executable
chmod +x "${REPO_DIR}/scripts/start-ue.sh" 2>/dev/null || true

echo ""
echo "======================================"
echo "  NUC #${UE_INDEX} setup complete!"
echo "======================================"
echo ""
echo "IMSI provisioned: ${IMSI}"
echo "  (ensure this IMSI is in Open5GS MongoDB on the gNB node)"
echo ""
echo "Next steps:"
echo "  1. Ensure gNodeB + 5GC are running on the gNB node"
echo "  2. Start UE:  sudo /local/repository/scripts/start-ue.sh"
echo ""
echo "Logs: /var/log/startup-ue.log"
echo "UE config: /etc/srsran/ue.conf"
