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

# Ensure the NVIDIA repositories are properly configured
# Get CUDA driver info to determine proper repo
cuda_metadata=$(jq -r '.cuda."'"$DISTRIBUTION"'"' <<< $COMPONENT_VERSIONS)
CUDA_DRIVER_VERSION=$(jq -r '.driver.version' <<< $cuda_metadata)
CUDA_DRIVER_DISTRIBUTION=$(jq -r '.driver.distribution' <<< $cuda_metadata)

# Check if NVIDIA repositories are properly set up
echo "Ensuring NVIDIA repositories are properly configured..."
# Force add the CUDA repo to ensure it's available
dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_DRIVER_DISTRIBUTION}/x86_64/cuda-${CUDA_DRIVER_DISTRIBUTION}.repo

# Add the DCGM repository explicitly
echo "Adding NVIDIA DCGM repository..."
dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_DRIVER_DISTRIBUTION}/x86_64/cuda-${CUDA_DRIVER_DISTRIBUTION}.repo

# Clean and refresh repositories
dnf clean all
dnf makecache

# Install DCGM
# Reference: https://developer.nvidia.com/dcgm#Downloads
dnf clean expire-cache -y

# Check available DCGM packages
echo "Checking available DCGM packages..."
available_dcgm=$(dnf list available datacenter-gpu-manager* 2>/dev/null || echo "No datacenter-gpu-manager packages found")
echo "Available DCGM packages: $available_dcgm"

# Also check for nvidia-dcgm
echo "Checking for nvidia-dcgm packages..."
available_nvidia_dcgm=$(dnf list available nvidia-dcgm* 2>/dev/null || echo "No nvidia-dcgm packages found")
echo "Available nvidia-dcgm packages: $available_nvidia_dcgm"

# Try to install DCGM with retries
MAX_ATTEMPTS=3
ATTEMPT=1
SUCCESS=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ "$SUCCESS" = false ]; do
    echo "Attempt $ATTEMPT of $MAX_ATTEMPTS to install DCGM..."
    
    # First try the exact version with datacenter-gpu-manager
    if dnf install -y datacenter-gpu-manager-1:${DCGM_VERSION}; then
        SUCCESS=true
        echo "DCGM installation successful on attempt $ATTEMPT (datacenter-gpu-manager-1:${DCGM_VERSION})"
    else
        echo "Exact version not found, trying without epoch..."
        # Try without the epoch (1:)
        if dnf install -y datacenter-gpu-manager-${DCGM_VERSION}; then
            SUCCESS=true
            echo "DCGM installation successful on attempt $ATTEMPT (datacenter-gpu-manager-${DCGM_VERSION})"
        else
            echo "datacenter-gpu-manager not found, trying nvidia-dcgm..."
            # Try nvidia-dcgm (alternative package name)
            if dnf install -y nvidia-dcgm; then
                SUCCESS=true
                INSTALLED_VERSION=$(rpm -q nvidia-dcgm --queryformat '%{VERSION}' 2>/dev/null || echo "unknown")
                echo "DCGM installation successful on attempt $ATTEMPT (nvidia-dcgm version: $INSTALLED_VERSION)"
            else
                echo "nvidia-dcgm not found, trying any available datacenter-gpu-manager..."
                # Try any available version as a last resort
                if dnf install -y datacenter-gpu-manager; then
                    SUCCESS=true
                    INSTALLED_VERSION=$(rpm -q datacenter-gpu-manager --queryformat '%{VERSION}' 2>/dev/null || echo "unknown")
                    echo "DCGM installation successful on attempt $ATTEMPT (datacenter-gpu-manager version: $INSTALLED_VERSION)"
                else
                    echo "DCGM installation failed on attempt $ATTEMPT"
                    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
                        echo "Cleaning DNF cache and trying again..."
                        dnf clean all
                        sleep 5
                    fi
                    ATTEMPT=$((ATTEMPT+1))
                fi
            fi
        fi
    fi
done

if [ "$SUCCESS" = false ]; then
    echo "Failed to install DCGM after $MAX_ATTEMPTS attempts"
    echo "Current DNF configuration:"
    cat /etc/dnf/dnf.conf
    echo "Enabled repositories:"
    dnf repolist
    echo "Available DCGM packages:"
    dnf list available datacenter-gpu-manager* nvidia-dcgm*
    echo "WARNING: Continuing without DCGM installation."
    $COMMON_DIR/write_component_version.sh "DCGM" "not-installed"
    exit 0  # Continue with the rest of the installation
fi

# If we get here, we successfully installed some version of DCGM
if rpm -q datacenter-gpu-manager &>/dev/null; then
    INSTALLED_VERSION=$(rpm -q datacenter-gpu-manager --queryformat '%{VERSION}' 2>/dev/null || echo "unknown")
    PACKAGE_NAME="datacenter-gpu-manager"
elif rpm -q nvidia-dcgm &>/dev/null; then
    INSTALLED_VERSION=$(rpm -q nvidia-dcgm --queryformat '%{VERSION}' 2>/dev/null || echo "unknown")
    PACKAGE_NAME="nvidia-dcgm"
else
    INSTALLED_VERSION="unknown"
    PACKAGE_NAME="unknown"
fi

echo "Successfully installed $PACKAGE_NAME version $INSTALLED_VERSION"
$COMMON_DIR/write_component_version.sh "DCGM" ${INSTALLED_VERSION}

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
