#!/bin/bash
# Rocky Linux HPC Image Validation Script
# Based on the azhpc-images test framework

set -e

echo "=== Rocky Linux HPC Image Validation Script ==="
echo "$(date)"

# Set environment variables
export HPC_ENV=/opt/azurehpc
export MODULE_FILES_ROOT=/usr/share/Modules/modulefiles

# For HPCX OSU benchmarks
export HPCX_OSU_DIR=/opt/hpcx-*/ompi/tests/osu-micro-benchmarks-*/mpi/pt2pt/

# Load component versions
if [ -f "$HPC_ENV/component_versions.txt" ]; then
    echo "=== Loading component versions from $HPC_ENV/component_versions.txt ==="
    COMPONENT_VERSIONS=$(cat $HPC_ENV/component_versions.txt)
    echo "$COMPONENT_VERSIONS" | jq '.'
    
    # Export all component versions as environment variables
    while read -r line; do
        if [[ ! -z "$line" ]]; then
            key=$(echo $line | cut -d= -f1)
            value=$(echo $line | cut -d= -f2-)
            export "VERSION_${key}=${value//\"}"
        fi
    done < <(echo "$COMPONENT_VERSIONS" | jq -r 'to_entries | .[] | "\(.key)=\(.value)"')
else
    echo "WARNING: Component versions file not found at $HPC_ENV/component_versions.txt"
fi

# Source the test definitions
source /data/src/azhpc-images/tests/test-definitions.sh

# Detect VM size
export VMSIZE=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text")
echo "VM Size: $VMSIZE"

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    export ID=$ID
    export VERSION_ID=$VERSION_ID
    echo "Linux Distribution: $ID $VERSION_ID"
else
    echo "ERROR: Cannot determine Linux distribution"
    exit 1
fi

# Run tests
echo "=== Running validation tests ==="

# Basic system validation
echo -e "\n--- Basic System Validation ---"
verify_basic_system_info

# MPI validation
echo -e "\n--- MPI Validation ---"
echo "Checking HPCX..."
verify_hpcx_installation || echo "HPCX verification failed"
echo "Checking MVAPICH2..."
verify_mvapich2_installation || echo "MVAPICH2 verification failed" 
echo "Checking Intel MPI 2021..."
verify_impi_2021_installation || echo "Intel MPI 2021 verification failed"
echo "Checking Open MPI..."
verify_ompi_installation || echo "Open MPI verification failed"

# CUDA validation
echo -e "\n--- CUDA Validation ---"
verify_cuda_installation || echo "CUDA verification failed"

# NCCL validation
echo -e "\n--- NCCL Validation ---"
verify_nccl_installation || echo "NCCL verification failed"

# GDRCopy validation
echo -e "\n--- GDRCopy Validation ---"
verify_gdrcopy_installation || echo "GDRCopy verification failed"

# Docker validation
echo -e "\n--- Docker Validation ---"
verify_docker_installation || echo "Docker verification failed"

# Compiler validation
echo -e "\n--- Compiler Validation ---"
verify_gcc_modulefile || echo "GCC verification failed"
verify_aocl_installation || echo "AOCL verification failed"
verify_aocc_installation || echo "AOCC verification failed"

# DCGM validation
echo -e "\n--- DCGM Validation ---"
verify_dcgm_installation || echo "DCGM verification failed"

# Services validation
echo -e "\n--- Services Validation ---"
verify_sku_customization_service || echo "SKU customization service verification failed"
verify_nvidia_fabricmanager_service || echo "NVIDIA Fabric Manager service verification failed"
verify_sunrpc_tcp_settings_service || echo "SunRPC TCP settings verification failed"

echo -e "\n=== Validation Complete ==="
echo "$(date)"
