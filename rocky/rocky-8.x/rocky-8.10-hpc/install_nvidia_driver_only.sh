#!/bin/bash
set -ex

# This script only installs the NVIDIA datacenter driver, which is redistributable
# It explicitly avoids installing non-redistributable components:
# - CUDA Toolkit
# - NVIDIA GDRCopy
# - NVIDIA Fabric Manager
# - NVIDIA GPUDirect RDMA

# Check if we're skipping NVIDIA components
if [ "$SKIP_NVIDIA_COMPONENTS" = "1" ]; then
    echo "SKIP_NVIDIA_COMPONENTS is set, installing only the redistributable NVIDIA driver"
else
    echo "Installing full NVIDIA driver and components"
    $COMMON_DIR/../rocky/rocky-8.x/common/install_nvidiagpudriver.sh
    exit 0
fi

# Install NVIDIA driver only (redistributable component)
nvidia_driver_metadata=$(jq -r '.nvidia."'"$DISTRIBUTION"'".driver' <<< $COMPONENT_VERSIONS)
NVIDIA_DRIVER_VERSION=$(jq -r '.version' <<< $nvidia_driver_metadata)
NVIDIA_DRIVER_SHA256=$(jq -r '.sha256' <<< $nvidia_driver_metadata)
NVIDIA_DRIVER_URL=https://us.download.nvidia.com/tesla/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run

echo "Installing ONLY the NVIDIA driver (redistributable) version ${NVIDIA_DRIVER_VERSION}"
$COMMON_DIR/download_and_verify.sh $NVIDIA_DRIVER_URL ${NVIDIA_DRIVER_SHA256}
bash NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run --silent --dkms
dkms install --no-depmod -m nvidia -v ${NVIDIA_DRIVER_VERSION} -k `uname -r` --force
$COMMON_DIR/write_component_version.sh "NVIDIA" ${NVIDIA_DRIVER_VERSION}

# load the nvidia-peermem coming as a part of NVIDIA GPU driver
# Reference - https://download.nvidia.com/XFree86/Linux-x86_64/510.85.02/README/nvidia-peermem.html
if ! modprobe nvidia-peermem; then echo "Failed to install module nvidia-peermem; continuing build anyway ... "; fi
# verify if loaded
if ! lsmod | grep nvidia_peermem; then echo "nvidia-peermem not loaded ... continuing build anyway ... "; fi

# cleanup downloaded files
rm -rf *.run
