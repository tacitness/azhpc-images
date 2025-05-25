#!/bin/bash

set -ex

source ${COMMON_DIR}/utilities.sh

aznhc_metadata=$(get_component_config "aznhc")
AZHC_VERSION=$(jq -r '.version' <<< $aznhc_metadata)

DEST_TEST_DIR=/opt/azurehpc/test
GPU_PLAT=$1

mkdir -p $DEST_TEST_DIR

pushd $DEST_TEST_DIR

# Check if directory already exists and handle it properly
if [ -d "azurehpc-health-checks" ]; then
    echo "Directory azurehpc-health-checks already exists, removing it for a fresh clone"
    rm -rf azurehpc-health-checks
fi

if [ "${GPU_PLAT}" = "NVIDIA" ]; then
   echo "Cloning Azure HPC Health Checks repository (NVIDIA GPU platform) version ${AZHC_VERSION}..."
   echo "Cloning Azure HPC Health Checks repository (NVIDIA GPU platform) version ${AZHC_VERSION}..."
   git clone https://github.com/Azure/azurehpc-health-checks.git --branch v$AZHC_VERSION

   pushd azurehpc-health-checks
   echo "Pulling health checks Docker container from MCR..."
   ./dockerfile/pull-image-acr.sh cuda
   popd
else
   echo "Cloning Azure HPC Health Checks repository (non-NVIDIA platform)..."
   git clone https://github.com/Azure/azurehpc-health-checks.git
   pushd azurehpc-health-checks
   echo "Building health checks Docker image for AMD..."
   ./dockerfile/build_image.sh rocm
   popd
fi

popd

echo "Recording health checks version information..."
$COMMON_DIR/write_component_version.sh "AZ_HEALTH_CHECKS" ${AZHC_VERSION}

echo "==============================================="
echo "Azure HPC Health Checks installation completed successfully!"
echo "Version: ${AZHC_VERSION}"
echo "Location: ${DEST_TEST_DIR}/azurehpc-health-checks"
echo "==============================================="
