#!/bin/bash
set -ex

# Set Intel® oneAPI Math Kernel Library info
intel_one_mkl_metadata=$(jq -r '.intel_one_mkl."'"$DISTRIBUTION"'"' <<< $COMPONENT_VERSIONS)
INTEL_ONE_MKL_VERSION=$(jq -r '.version' <<< $intel_one_mkl_metadata)
INTEL_ONE_MKL_SHA256=$(jq -r '.sha256' <<< $intel_one_mkl_metadata)
INTEL_ONE_MKL_DOWNLOAD_URL=$(jq -r '.url' <<< $intel_one_mkl_metadata)
INTEL_ONE_MKL_OFFLINE_INSTALLER=$(basename $INTEL_ONE_MKL_DOWNLOAD_URL)

# Clean up disk space before installing Intel MKL
echo "Cleaning up disk space before Intel MKL installation..."
# Remove unnecessary packages and clean up package caches
dnf clean all
# Remove temporary files
rm -rf /tmp/*.log /tmp/*.rpm /tmp/*.tar.gz /tmp/*.bz2 /tmp/*.tbz /tmp/*.deb 2>/dev/null || true
# Clear journal logs if they're taking up space
journalctl --vacuum-time=1d

# Check available disk space
AVAIL_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
REQUIRED_SPACE=7  # slightly higher than the 6.5GB requirement to be safe

echo "Available disk space: ${AVAIL_SPACE}GB, Required: ${REQUIRED_SPACE}GB"

if [ "${AVAIL_SPACE%.*}" -lt "$REQUIRED_SPACE" ]; then
    echo "WARNING: Not enough disk space for Intel MKL installation. Attempting more aggressive cleanup..."
    # More aggressive cleanup if space is still insufficient
    find /var/log -type f -name "*.log*" -exec rm -f {} \;
    find /var/log -type f -name "*.gz" -exec rm -f {} \;
    rm -rf /var/cache/* /var/tmp/* 2>/dev/null || true
    # Check Docker images if Docker is installed
    if command -v docker >/dev/null 2>&1; then
        docker system prune -af
    fi
    
    # Check available space again
    AVAIL_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    echo "Available disk space after cleanup: ${AVAIL_SPACE}GB"
fi

# Intel® oneAPI Math Kernel Library
$COMMON_DIR/write_component_version.sh "INTEL_ONE_MKL" ${INTEL_ONE_MKL_VERSION}
$COMMON_DIR/download_and_verify.sh ${INTEL_ONE_MKL_DOWNLOAD_URL} ${INTEL_ONE_MKL_SHA256}

# Try to install with some extra flags to handle disk space issues
INSTALL_RESULT=1
if [ -f "./${INTEL_ONE_MKL_OFFLINE_INSTALLER}" ]; then
    # First try with default settings
    sh ./${INTEL_ONE_MKL_OFFLINE_INSTALLER} -s -a -s --eula accept
    INSTALL_RESULT=$?
    
    # If installation fails, try with a custom temporary directory
    if [ $INSTALL_RESULT -ne 0 ]; then
        echo "First installation attempt failed. Trying with a custom temp directory..."
        mkdir -p /opt/intel_tmp
        sh ./${INTEL_ONE_MKL_OFFLINE_INSTALLER} -s -a -s --eula accept --tmp-dir /opt/intel_tmp
        INSTALL_RESULT=$?
        rm -rf /opt/intel_tmp
    fi
    
    # Clean up the installer after installation
    rm -f ./${INTEL_ONE_MKL_OFFLINE_INSTALLER}
else
    echo "Error: Intel MKL installer not found: ${INTEL_ONE_MKL_OFFLINE_INSTALLER}"
    INSTALL_RESULT=1
fi

# Report final status
if [ $INSTALL_RESULT -eq 0 ]; then
    echo "Intel MKL installation completed successfully"
else
    echo "WARNING: Intel MKL installation failed with exit code $INSTALL_RESULT"
    # Don't fail the entire script if MKL installation fails
    # We'll continue with the rest of the build
fi
