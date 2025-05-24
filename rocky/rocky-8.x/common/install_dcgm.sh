#!/bin/bash
set -ex

# Set DCGM version info
dcgm_metadata=$(jq -r '.dcgm."'"$DISTRIBUTION"'"' <<< $COMPONENT_VERSIONS)
DCGM_VERSION=$(jq -r '.version' <<< $dcgm_metadata)

# Clean up DNF configuration if needed
if [ -f "/etc/dnf/dnf.conf" ]; then
    # Check for and fix common issues in dnf.conf
    if grep -q "skip_if_unavailable=.*openmpi" /etc/dnf/dnf.conf; then
        echo "Fixing DNF configuration skip_if_unavailable line..."
        sed -i 's/^skip_if_unavailable=.*/skip_if_unavailable=False/' /etc/dnf/dnf.conf
    fi
fi

# Install DCGM
# Reference: https://developer.nvidia.com/dcgm#Downloads
# the repo is already added during nvidia/ cuda installations
dnf clean expire-cache -y
# Try to install DCGM with retries
MAX_ATTEMPTS=3
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ "$SUCCESS" = false ]; do
    echo "Attempt $ATTEMPT of $MAX_ATTEMPTS to install DCGM..."
    if dnf install -y datacenter-gpu-manager-1:${DCGM_VERSION}; then
        SUCCESS=true
        echo "DCGM installation successful on attempt $ATTEMPT"
    else
        echo "DCGM installation failed on attempt $ATTEMPT"
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
            echo "Cleaning DNF cache and trying again..."
            dnf clean all
            sleep 5
        fi
        ATTEMPT=$((ATTEMPT+1))
    fi
done

if [ "$SUCCESS" = false ]; then
    echo "Failed to install DCGM after $MAX_ATTEMPTS attempts"
    echo "Current DNF configuration:"
    cat /etc/dnf/dnf.conf
    exit 1
fi

$COMMON_DIR/write_component_version.sh "DCGM" ${DCGM_VERSION}

# Enable the dcgm service
systemctl enable nvidia-dcgm
#systemctl start nvidia-dcgm
# Check if the service is active
#systemctl is-active --quiet nvidia-dcgm
#error_code=$?
#if [ ${error_code} -ne 0 ]
#then
#    echo "DCGM is inactive!"
#    exit ${error_code}
#fi
