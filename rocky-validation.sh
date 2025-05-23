#!/bin/bash
# Rocky Linux HPC Image Validation Script
# Based on the azhpc-images test framework

set -e

echo "=== Rocky Linux HPC Image Validation Script ==="
echo "$(date)"

# Set environment variables
export HPC_ENV=/opt/azurehpc
export MODULE_FILES_ROOT=/usr/share/Modules/modulefiles

# For HPCX OSU benchmarks - search for it dynamically
if [ -d "/opt/hpcx-" ]; then
    # Find the OSU benchmarks directory dynamically
    OSU_DIRS=$(find /opt/hpcx-* -type d -path "*/ompi/tests/osu-micro-benchmarks-*/mpi/pt2pt" 2>/dev/null)
    if [ -n "$OSU_DIRS" ]; then
        export HPCX_OSU_DIR=$(echo "$OSU_DIRS" | head -1)
        echo "Found OSU benchmarks at: $HPCX_OSU_DIR"
    else
        echo "Warning: OSU benchmarks not found, HPCX tests may fail"
        export HPCX_OSU_DIR=""
    fi
else
    echo "Warning: HPCX installation directory not found, HPCX tests may fail"
    export HPCX_OSU_DIR=""
fi

# Load component versions
if [ -f "$HPC_ENV/component_versions.txt" ]; then
    echo "=== Loading component versions from $HPC_ENV/component_versions.txt ==="
    COMPONENT_VERSIONS=$(cat $HPC_ENV/component_versions.txt)
    
    # Check if file is valid JSON
    if jq -e '.' >/dev/null 2>&1 <<< "$COMPONENT_VERSIONS"; then
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
        echo "WARNING: Invalid JSON in component versions file"
    fi
else
    echo "WARNING: Component versions file not found at $HPC_ENV/component_versions.txt"
fi

# Determine the script's location and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Source the test definitions
if [ -f "$REPO_ROOT/tests/test-definitions.sh" ]; then
    source "$REPO_ROOT/tests/test-definitions.sh"
else
    echo "ERROR: Cannot find test-definitions.sh in $REPO_ROOT/tests/"
    echo "Please make sure you are running this script from the root of the azhpc-images repository"
    exit 1
fi

# Function to verify basic system information
function verify_basic_system_info {
    # Check kernel version
    echo "Kernel version: $(uname -r)"
    uname -a
    check_exit_code "Kernel version" "Failed to get kernel version"
    
    # Check OS release information
    echo "OS Release information:"
    cat /etc/os-release
    check_exit_code "OS release info" "Failed to get OS release info"
    
    # Check CPU information
    echo "CPU information:"
    lscpu | grep -E "Model name|CPU\(s\)|Thread|Core|Socket"
    check_exit_code "CPU info" "Failed to get CPU info"
    
    # Check memory information
    echo "Memory information:"
    free -h
    check_exit_code "Memory info" "Failed to get memory info"
    
    # Check disk information
    echo "Disk information:"
    df -h
    check_exit_code "Disk info" "Failed to get disk info"
    
    # Check installed modules
    echo "Installed modules:"
    module avail
    check_exit_code "Module list" "Failed to list modules"
    
    # Check if we're running in Azure
    if curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null; then
        echo "Running as Azure VM: Yes"
    else
        echo "Running as Azure VM: No"
    fi
    
    # Check the core packages specific to Rocky Linux
    echo "Checking core Rocky Linux HPC packages:"
    rpm -qa | grep -E "openpbs|rocm|mpich|mvapich|ompi|impi|hpcx"
    # Don't check exit code as this may return nothing depending on packages installed
    
    # Check SELinux status
    echo "SELinux status:"
    getenforce || echo "SELinux not available"
    
    # Check firewall status
    echo "Firewall status:"
    systemctl status firewalld || echo "Firewall service not available"
}

# Detect VM size with better error handling
export VMSIZE=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text" 2>/dev/null || echo "unknown")
if [ "$VMSIZE" == "unknown" ]; then
    echo "Warning: Could not determine VM size from metadata service. Some tests may be skipped."
else
    echo "VM Size: $VMSIZE"
fi

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

# Network validation
echo -e "\n--- Network Validation ---"
verify_ofed_installation || echo "OFED installation verification failed"
verify_ib_device_status || echo "IB device status verification failed"
verify_ipoib_status || echo "IPoIB status verification failed"

# Additional checks for Rocky Linux
echo -e "\n--- Rocky Linux-specific Validation ---"
if [ "$ID" == "rocky" ]; then
    # Check for DNF and YUM
    echo "Checking package managers:"
    which dnf && dnf --version | head -1 || echo "DNF not found"
    which yum && yum --version | head -1 || echo "YUM not found"
    
    # Check for common Rocky Linux services
    echo "Checking Rocky Linux services:"
    systemctl status chronyd || echo "chronyd not active"
    
    # Check for SELinux packages
    echo "Checking SELinux packages:"
    rpm -qa | grep -E "selinux" || echo "No SELinux packages found"
fi

echo -e "\n=== Validation Complete ==="
echo "$(date)"
