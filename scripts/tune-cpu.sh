#!/bin/bash
# CPU performance tuning for real-time SDR operation (from srslte-otalab)

# Set governor to performance
for ((i=0;i<$(nproc);i++)); do sudo cpufreq-set -c $i -r -g performance; done

# Disable C-states
sudo cpupower idle-set -D 2

# Disable turbo boost
cores=$(cat /proc/cpuinfo | grep processor | awk '{print $3}')
for core in $cores; do
    sudo wrmsr -p${core} 0x1a0 0x4000850089
    state=$(sudo rdmsr -p${core} 0x1a0 -f 38:38)
    if [[ $state -eq 1 ]]; then
        echo "core ${core}: turbo disabled"
    else
        echo "core ${core}: turbo enabled"
    fi
done
