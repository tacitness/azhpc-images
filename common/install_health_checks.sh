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
   git clone https://github.com/Azure/azurehpc-health-checks.git --branch v$AZHC_VERSION

   pushd azurehpc-health-checks
   echo "Pulling health checks Docker container from MCR..."
   ./dockerfile/pull-image-acr.sh cuda
   popd
elif [ "${GPU_PLAT}" = "AMD" ]; then
   echo "Cloning Azure HPC Health Checks repository (non-NVIDIA platform)..."
   git clone https://github.com/Azure/azurehpc-health-checks.git
   pushd azurehpc-health-checks
   
   # Fix for AMD/ROCM builds - skip Docker image build if HPC-X is not found
   echo "Checking for HPC-X installation for AMD build..."
   HPCX_POSSIBLE_DIRS=( 
     "/opt/hpcx-v2.18-gcc-mlnx_ofed-redhat8-x86_64" 
     "/opt/hpcx-v2.18-gcc-mlnx_ofed-ubuntu22.04-x86_64"
     "/opt/hpcx-v2.19-gcc-mlnx_ofed-redhat8-x86_64"
     "/opt/hpcx-v2.18-gcc-mlnx_ofed-redhat8-cuda12-x86_64"
     "/opt/hpcx-v"*"-gcc-mlnx_ofed-"*"-x86_64"
   )
   
   HPCX_FOUND=false
   for dir in "${HPCX_POSSIBLE_DIRS[@]}"; do
     if [ -d "$dir" ]; then
       echo "Found HPC-X installation at $dir"
       export HPCX_MPI_DIR="$dir"
       HPCX_FOUND=true
       break
     fi
   done
   
   if [ "$HPCX_FOUND" = true ]; then
     echo "Building health checks Docker image for AMD..."
     # Keep the detected HPCX_MPI_DIR from the loop above
     echo "Using HPCX_MPI_DIR=$HPCX_MPI_DIR"
     
     # Create root-level symlink for Docker build compatibility
     echo "Creating root-level symlink for Docker build..."
     ln -sf "$HPCX_MPI_DIR" "/hpcx-v2.18-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64"
     
     # Run the build script with explicit environment variable
     echo "Running build script with HPCX_MPI_DIR set..."
     ./dockerfile/build_image.sh rocm || {
       echo "Warning: Docker build failed, but continuing installation"
       # Clean up symlink if build fails
       rm -f "/hpcx-v2.18-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64"
     }
     
     # Clean up root-level symlink after build
     rm -f "/hpcx-v2.18-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64"
   else
     echo "Warning: HPC-X installation not found, skipping Docker image build."
     echo "Manual build will be required later using: cd ${DEST_TEST_DIR}/azurehpc-health-checks && ./dockerfile/build_image.sh rocm"
   fi
   popd
else
   echo "Cloning Azure HPC Health Checks repository (no GPU platform)..."
   git clone https://github.com/Azure/azurehpc-health-checks.git
   pushd azurehpc-health-checks
   echo "Skipping Docker image build as no GPU platform was specified"
   popd
fi

popd

echo "Recording health checks version information..."
$COMMON_DIR/write_component_version.sh "AZ_HEALTH_CHECKS" ${AZHC_VERSION}

echo "==============================================="
echo "Azure HPC Health Checks installation completed!"
echo "Version: ${AZHC_VERSION}"
echo "Location: ${DEST_TEST_DIR}/azurehpc-health-checks"
if [ "${GPU_PLAT}" != "NVIDIA" ] && [ "$HPCX_FOUND" = false ]; then
  echo "NOTE: Docker image for AMD was not built due to missing HPC-X."
  echo "To build manually later: cd ${DEST_TEST_DIR}/azurehpc-health-checks && ./dockerfile/build_image.sh rocm"
fi
echo "==============================================="
