#!/bin/bash
# Rocky Linux HPC Image Validation Script
# Based on the azhpc-images test framework

# Check if running as root and suggest alternatives
if [ "$EUID" -eq 0 ]; then
    echo "NOTE: Running as root. Some MPI tests may fail."
    echo "Consider running as a regular user with: sudo -u rocky $0"
fi

# Use -e to exit on first error, or comment out to continue through errors
#set -e

# Initialize error counter
ERROR_COUNT=0

# Determine if we're running on actual HPC hardware
HAS_INFINIBAND=0
if lspci | grep -i infiniband >/dev/null; then
    HAS_INFINIBAND=1
    echo "Detected InfiniBand hardware - will perform full hardware tests"
else
    echo "No InfiniBand hardware detected - will perform basic validation only"
fi

echo "=== Rocky Linux HPC Image Validation Script ==="
echo "$(date)"

# Set environment variables
export HPC_ENV=/opt/azurehpc
export MODULE_FILES_ROOT=/usr/share/Modules/modulefiles

# Allow MPI to run as root (for validation purposes only)
export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

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

# Source our local helper functions
if [ -f "$SCRIPT_DIR/rocky-validation-functions.sh" ]; then
    source "$SCRIPT_DIR/rocky-validation-functions.sh"
fi

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
# Create custom HPCX verification function with root support
function verify_hpcx_installation_root {
    # verify mpi installations and their modulefiles
    module avail

    check_exists "${MODULE_FILES_ROOT}/mpi/hpcx"
    
    # Use appropriate transport based on hardware
    local UCX_TRANSPORT="tcp"
    if [ "$HAS_INFINIBAND" -eq 1 ]; then
        UCX_TRANSPORT="rc"
    fi
    
    echo "Using UCX transport: $UCX_TRANSPORT"
    
    module load mpi/hpcx
    mpirun --allow-run-as-root -np 2 --map-by ppr:2:node -x UCX_TLS=$UCX_TRANSPORT ${HPCX_OSU_DIR}/osu_latency
    check_exit_code "HPC-X" "Failed to run HPC-X"
    module unload mpi/hpcx

    check_exists "${MODULE_FILES_ROOT}/mpi/hpcx-pmix"

    module load mpi/hpcx-pmix
    mpirun --allow-run-as-root -np 2 --map-by ppr:2:node -x UCX_TLS=$UCX_TRANSPORT ${HPCX_OSU_DIR}/osu_latency
    check_exit_code "HPC-X with PMIx" "Failed to run HPC-X with PMIx"
    module unload mpi/hpcx-pmix
    module purge
}
verify_hpcx_installation_root || echo "HPCX verification failed"

echo "Checking MVAPICH2..."
function verify_mvapich2_installation_root {
    check_exists "${MODULE_FILES_ROOT}/mpi/mvapich2"

    module load mpi/mvapich2
    # Env MV2_FORCE_HCA_TYPE=22 explicitly selects EDR
    local mvapich2_omb_path=${MPI_HOME}/libexec/osu-micro-benchmarks/mpi/pt2pt
    mpiexec -np 2 -ppn 2 -env MV2_USE_SHARED_MEM=0 -env MV2_FORCE_HCA_TYPE=22 ${mvapich2_omb_path}/osu_latency
    check_exit_code "MVAPICH2 ${VERSION_MVAPICH2}" "Failed to run MVAPICH2"
    module unload mpi/mvapich2
}
run_test_with_error_handling "MVAPICH2" verify_mvapich2_installation_root
echo "Checking Intel MPI 2021..."
function verify_impi_2021_installation_root {
    check_exists "${MODULE_FILES_ROOT}/mpi/impi-2021"
    
    module load mpi/impi-2021
    mpiexec -np 2 -ppn 2 -env FI_PROVIDER=mlx -env I_MPI_SHM=0 ${MPI_BIN}/IMB-MPI1 pingpong
    check_exit_code "Intel MPI 2021 ${VERSION_IMPI}" "Failed to run Intel MPI 2021"
    module unload mpi/impi-2021
}
run_test_with_error_handling "Intel MPI 2021" verify_impi_2021_installation_root
echo "Checking Open MPI..."
function verify_ompi_installation_root {
    check_exists "${MODULE_FILES_ROOT}/mpi/openmpi"
    check_exists "/opt/openmpi-${VERSION_OMPI}"
    check_exit_code "Open MPI ${VERSION_OMPI}" "Failed to run Open MPI"
}
run_test_with_error_handling "Open MPI" verify_ompi_installation_root

# CUDA validation
echo -e "\n--- CUDA Validation ---"
verify_cuda_installation || echo "CUDA verification failed"

# NCCL validation
echo -e "\n--- NCCL Validation ---"
# Create custom NCCL verification function with root support
function verify_nccl_installation_root {
    # Print nccl.conf if it exists
    if test -f /etc/nccl.conf; then
        cat /etc/nccl.conf
    fi

    # Use appropriate transport based on hardware
    local UCX_TRANSPORT="tcp"
    if [ "$HAS_INFINIBAND" -eq 1 ]; then
        UCX_TRANSPORT="rc"
    fi
    
    echo "Using UCX transport: $UCX_TRANSPORT"
    
    module load mpi/hpcx

    case ${VMSIZE} in
        standard_nc24rs_v3) mpirun --allow-run-as-root -np 4 \
            -x LD_LIBRARY_PATH \
            --map-by ppr:4:node \
            -mca coll_hcoll_enable 0 \
            -x UCX_TLS=$UCX_TRANSPORT \
            -x CUDA_DEVICE_ORDER=PCI_BUS_ID \
            -x NCCL_SOCKET_IFNAME=eth0 \
            -x NCCL_DEBUG=WARN \
            /opt/nccl-tests/build/all_reduce_perf -b1K -f2 -g1 -e 4G;;
        standard_nd40rs_v2 | standard_nd96*v4 | standard_nc*ads_a100_v4) mpirun --allow-run-as-root -np 8 \
            --map-by ppr:8:node \
            -x LD_LIBRARY_PATH=/usr/local/nccl-rdma-sharp-plugins/lib:$LD_LIBRARY_PATH \
            -mca coll_hcoll_enable 0 \
            -x UCX_TLS=$UCX_TRANSPORT \
            -x CUDA_DEVICE_ORDER=PCI_BUS_ID \
            -x NCCL_SOCKET_IFNAME=eth0 \
            -x NCCL_DEBUG=WARN \
            -x NCCL_NET_GDR_LEVEL=5 \
            /opt/nccl-tests/build/all_reduce_perf -b1K -f2 -g1 -e 4G;;
        *) echo "Skipping NCCL test for VM size: ${VMSIZE}";;
    esac
    check_exit_code "NCCL ${VERSION_NCCL}" "Failed to run NCCL all reduce perf"
    
    module unload mpi/hpcx
}

verify_nccl_installation_root || echo "NCCL verification failed"

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

# Create a summary of validation results
echo -e "\n=== Validation Summary ==="
if [ -n "$ERROR_COUNT" ] && [ "$ERROR_COUNT" -gt 0 ]; then
    echo "Validation completed with $ERROR_COUNT errors."
    echo "Review the output above for details on failed components."
    
    if [ "$HAS_INFINIBAND" -eq 0 ]; then
        echo ""
        echo "NOTE: This machine does not have InfiniBand hardware."
        echo "Some errors are expected when validating on non-HPC hardware."
        echo "For complete validation, run this script on an Azure HPC VM instance."
        echo "Consider using: Standard_HB120rs_v3, Standard_ND40rs_v2, or similar."
    fi
else
    echo "All validation tests completed successfully!"
fi
echo -e "\n=== Validation Complete ==="
echo "$(date)"
