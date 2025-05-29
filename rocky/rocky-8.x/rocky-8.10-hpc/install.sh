#!/bin/bash
set -e

# Initialize timing array and variables
declare -A STAGE_TIMES
declare -A STAGE_STATUS
TOTAL_START_TIME=$(date +%s)
CURRENT_STAGE=""

# Function to start timing a stage
start_stage() {
    CURRENT_STAGE="$1"
    echo "=============================================================="
    echo "STARTING STAGE: $CURRENT_STAGE"
    echo "=============================================================="
    STAGE_START_TIME=$(date +%s)
    STAGE_STATUS["$CURRENT_STAGE"]="RUNNING"
}

# Function to end timing a stage
end_stage() {
    STAGE_END_TIME=$(date +%s)
    DURATION=$((STAGE_END_TIME - STAGE_START_TIME))
    STAGE_TIMES["$CURRENT_STAGE"]=$DURATION
    STAGE_STATUS["$CURRENT_STAGE"]="COMPLETED"
    
    # Format duration as HH:MM:SS
    HOURS=$((DURATION / 3600))
    MINUTES=$(( (DURATION % 3600) / 60 ))
    SECONDS=$((DURATION % 60))
    FORMATTED_TIME=$(printf "%02d:%02d:%02d" $HOURS $MINUTES $SECONDS)
    
    echo "=============================================================="
    echo "COMPLETED STAGE: $CURRENT_STAGE in $FORMATTED_TIME"
    echo "=============================================================="
}

# Function to mark a stage as skipped
skip_stage() {
    local stage_name="$1"
    STAGE_TIMES["$stage_name"]="SKIPPED"
    STAGE_STATUS["$stage_name"]="SKIPPED"
    echo "=============================================================="
    echo "SKIPPED STAGE: $stage_name"
    echo "=============================================================="
}

# Function to print build summary
print_build_summary() {
    TOTAL_END_TIME=$(date +%s)
    TOTAL_DURATION=$((TOTAL_END_TIME - TOTAL_START_TIME))
    
    # Format total duration
    TOTAL_HOURS=$((TOTAL_DURATION / 3600))
    TOTAL_MINUTES=$(( (TOTAL_DURATION % 3600) / 60 ))
    TOTAL_SECONDS=$((TOTAL_DURATION % 60))
    TOTAL_FORMATTED_TIME=$(printf "%02d:%02d:%02d" $TOTAL_HOURS $TOTAL_MINUTES $TOTAL_SECONDS)
    
    # Get system information
    CPU_COUNT=$(nproc)
    if [ -f /var/lib/cloud/instance/instance-id.txt ]; then
        INSTANCE_ID=$(cat /var/lib/cloud/instance/instance-id.txt)
    else
        INSTANCE_ID="Unknown"
    fi
    
    if [ -f /etc/cloud/cloud.cfg ]; then
        VM_SIZE=$(grep vm_size /etc/cloud/cloud.cfg 2>/dev/null | awk '{print $2}' || echo "Unknown")
    else
        VM_SIZE=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text" || echo "Unknown")
    fi
    
    # Print summary header
    echo ""
    echo "=================================================================="
    echo "                   BUILD SUMMARY REPORT                           "
    echo "=================================================================="
    echo "Instance ID: $INSTANCE_ID"
    echo "VM Size: $VM_SIZE"
    echo "CPU Count: $CPU_COUNT"
    echo "Total Build Time: $TOTAL_FORMATTED_TIME"
    echo "=================================================================="
    echo "Stage                                    | Status    | Duration    "
    echo "------------------------------------------------------------------"
    
    # Print each stage's timing
    for stage in "${!STAGE_TIMES[@]}"; do
        status=${STAGE_STATUS["$stage"]}
        time=${STAGE_TIMES["$stage"]}
        
        if [ "$time" == "SKIPPED" ]; then
            formatted_time="  SKIPPED  "
        else
            # Format time as HH:MM:SS
            hours=$((time / 3600))
            minutes=$(( (time % 3600) / 60 ))
            seconds=$((time % 60))
            formatted_time=$(printf "%02d:%02d:%02d" $hours $minutes $seconds)
        fi
        
        # Pad stage name for alignment
        printf "%-40s | %-9s | %s\n" "$stage" "$status" "$formatted_time"
    done
    
    echo "=================================================================="
    echo "Total Build Time: $TOTAL_FORMATTED_TIME"
    echo "=================================================================="
}

# Register trap to ensure summary is printed even if script exits early
trap print_build_summary EXIT

# Clean up DNF config at the beginning - thorough approach to fix corrupt configuration
start_stage "DNF Configuration Cleanup"
if [ -f "/etc/dnf/dnf.conf" ]; then
    echo "Cleaning up DNF configuration..."
    
    # Check if skip_if_unavailable line is corrupted with openmpi perftest
    if grep -q "skip_if_unavailable=.*openmpi" /etc/dnf/dnf.conf; then
        echo "Found corrupted skip_if_unavailable line, recreating DNF configuration file..."
        # Create a completely new dnf.conf with basic settings
        cat > /etc/dnf/dnf.conf.new << EOF
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=True
skip_if_unavailable=False
EOF
        # If there was a valid exclude line, preserve it
        if grep -q "^exclude=" /etc/dnf/dnf.conf; then
            grep "^exclude=" /etc/dnf/dnf.conf >> /etc/dnf/dnf.conf.new
        fi
        # Backup original file and replace with the new one
        cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.corrupted
        mv /etc/dnf/dnf.conf.new /etc/dnf/dnf.conf
    else
        # Backup the original file
        cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.bak
        # Fix any corrupted lines and ensure clean configuration
        grep -v "^exclude=" /etc/dnf/dnf.conf | grep -v "openmpi perftest" > /etc/dnf/dnf.conf.clean
        mv /etc/dnf/dnf.conf.clean /etc/dnf/dnf.conf
        # Ensure skip_if_unavailable is properly set without extra content
        if grep -q "^skip_if_unavailable=" /etc/dnf/dnf.conf; then
            sed -i 's/^skip_if_unavailable=.*/skip_if_unavailable=False/' /etc/dnf/dnf.conf
        fi
    fi
    
    echo "DNF configuration cleaned"
fi
end_stage

# Complete Intel MPI cleanup before install
start_stage "Intel MPI Cleanup"
intel_cleanup() {
  echo "Performing thorough Intel MPI cleanup..."
  
  # Remove main Intel directories
  rm -rf /opt/intel
  rm -rf /opt/intel_licenses
  rm -rf /var/intel 
  rm -rf /tmp/root/intel*

  # Remove package manager references
  if command -v rpm &> /dev/null; then
    rpm -qa | grep -i intel | xargs -r rpm -e --nodeps
  fi
  
  # Clean up potential hidden directories
  rm -rf ~/.intel
  rm -rf ~/.pki/nssdb/*intel*
  rm -rf hpcx-v2.18-gcc-mlnx_ofed-redhat8-cuda12-x86_64* MLNX_OFED_LINUX-24.10-1.1.4.0-rhel8.10-x86_64* mvapich2* openmpi* ucx* 

  # Clean installer caches
  rm -rf /tmp/intel*
  rm -rf /tmp/*offline*
  rm -rf /tmp/tmpjsonlogdir.HiIHTH/intel-sw-install-history.json.log 

  # Remove modulefiles
  rm -rf /usr/share/Modules/modulefiles/mpi/impi*
  
  # Additional Intel directories
  rm -rf /etc/intel
  rm -rf /var/intel
  
  # Clean up potential environment settings
  unset I_MPI_ROOT
  unset INTEL_LICENSE_FILE
  unset IPPROOT
  unset IPP_TARGET_ARCH
  unset MKLROOT
  
  # Flush shared library cache
  ldconfig
  
  echo "Intel MPI cleanup completed"
}
intel_cleanup
end_stage

# Clean up NCCL related files and directories before install
start_stage "NCCL Cleanup"
nccl_cleanup() {
  echo "Performing NCCL cleanup..."
  
  # Clean up NCCL plugins and test directories
  rm -rf /usr/local/nccl-rdma-sharp-plugins
  rm -rf nccl-rdma-sharp-plugins
  rm -rf nccl-tests
  rm -rf /opt/nccl-tests
  
  # Clean up any leftover build directories or files
  rm -rf /tmp/nccl-*
  rm -rf /tmp/v*.tar.gz
  
  echo "NCCL cleanup completed"
}
nccl_cleanup
end_stage

# Clear non-redistributable GPU software - ONLY for public distribution
# When SKIP_NVIDIA_COMPONENTS=1:
#   - INSTALLED: NVIDIA Datacenter Driver (redistributable)
#   - SKIPPED: CUDA Toolkit, NVIDIA DCGM, NVIDIA Fabric Manager, GDRCopy, GPUDirect RDMA
SKIP_NVIDIA_COMPONENTS=1

# install pre-requisites
start_stage "Prerequisites Installation"
./install_prerequisites.sh
end_stage

# set properties
start_stage "Setting Properties"
source ./set_properties.sh
end_stage

# install utils
start_stage "Utils Installation"
./install_utils.sh
end_stage

# install Lustre client
start_stage "Lustre Client Installation"
$ROCKY_COMMON_DIR/install_lustre_client.sh "8"
end_stage

# install compilers
start_stage "GCC Installation"
./install_gcc.sh
end_stage

# install mellanox ofed
start_stage "Mellanox OFED Installation"
./install_mellanoxofed.sh
end_stage

# install PMIX
start_stage "PMIX Installation"
$ROCKY_COMMON_DIR/../rocky-8.x/common/install_pmix.sh
end_stage

# install mpi libraries
start_stage "MPI Libraries Installation"
echo "DEBUG: MPIS: Entering ./install_mpis.sh"
env | colrm 180
pwd
./install_mpis.sh
end_stage

# Install NVIDIA components
if [ "$SKIP_NVIDIA_COMPONENTS" = "1" ]; then
    start_stage "NVIDIA Driver Installation (Redistributable Only)"
    echo "Installing only redistributable NVIDIA driver"
    # Install only the NVIDIA driver (redistributable)
    ./install_nvidia_driver_only.sh
    end_stage

    skip_stage "NVIDIA GPU Driver Full Installation (Non-Redistributable)"
else
    skip_stage "NVIDIA Driver Installation (Redistributable Only)"

    start_stage "NVIDIA GPU Driver Full Installation (Non-Redistributable)"
    # Install all NVIDIA components including non-redistributable ones
    ./install_nvidiagpudriver.sh
    end_stage
fi

# install AMD tuned libraries
start_stage "AMD Libraries Installation"
./install_amd_libs.sh
end_stage

# install Intel libraries
start_stage "Intel Libraries Installation"
./install_intel_libs.sh
end_stage

# cleanup downloaded tarballs - clear some space
start_stage "Download Cleanup"
rm -rf *.tgz *.bz2 *.tbz *.tar.gz *.run *.deb *_offline.sh
rm -rf /tmp/MLNX_OFED_LINUX* /tmp/*conf*
rm -rf /var/intel/ /var/cache/*
#rm -Rf -- */
end_stage

# Install NCCL (redistributable)
if [ "$SKIP_NVIDIA_COMPONENTS" = "1" ]; then
    start_stage "NCCL Installation (Redistributable)"
    echo "Installing redistributable version of NCCL"
    ./install_nccl_redist.sh
    end_stage

    skip_stage "NCCL Installation (Full with CUDA)"
else
    skip_stage "NCCL Installation (Redistributable)"

    start_stage "NCCL Installation (Full with CUDA)"
    echo "Installing full NCCL with CUDA dependencies"
    ./install_nccl.sh
    end_stage
fi

# NVIDIA container components (non-redistributable)
if [ "$SKIP_NVIDIA_COMPONENTS" != "1" ]; then
    start_stage "NVIDIA Docker Container Installation"
    # Install NVIDIA docker container
    $COMMON_DIR/../rocky/rocky-8.x/common/install_docker.sh
    end_stage

    start_stage "NVIDIA DCGM Installation"
    # Install DCGM
    ./install_dcgm.sh
    end_stage
else
    skip_stage "NVIDIA Docker Container Installation"
    skip_stage "NVIDIA DCGM Installation"
    echo "Skipping non-redistributable NVIDIA components (Docker container toolkit, DCGM)"
fi

# optimizations
start_stage "HPC Tuning"
./hpc-tuning.sh
end_stage

# install persistent rdma naming
start_stage "Persistent RDMA Naming"
$COMMON_DIR/install_azure_persistent_rdma_naming.sh
end_stage

# add udev rule
start_stage "udev Rules"
$COMMON_DIR/../rocky/common/add-udev-rules.sh
end_stage

# add interface rules
start_stage "Network Configuration"
$COMMON_DIR/../rocky/common/network-config.sh
end_stage

# install diagnostic script
start_stage "HPC Diagnostics Installation"
$COMMON_DIR/install_hpcdiag.sh
end_stage

# install monitoring tools
start_stage "Monitoring Tools Installation"
$COMMON_DIR/../rocky/common/install_monitoring_tools.sh
end_stage

# install Azure/NHC Health Checks
start_stage "Health Checks Installation"
$COMMON_DIR/install_health_checks.sh
end_stage

# copy test file
start_stage "Test File Copy"
$COMMON_DIR/copy_test_file.sh
end_stage

# disable cloud-init
start_stage "Cloud-Init Disabling"
$ROCKY_COMMON_DIR/disable_cloudinit.sh
end_stage

# SKU Customization
start_stage "SKU Customizations"
$COMMON_DIR/setup_sku_customizations.sh
end_stage

# clear history
start_stage "History Cleanup"
# Uncomment the line below if you are running this on a VM
$COMMON_DIR/clear_history.sh
end_stage

# Called out as alma only patch, disabling namespaces is not likely what we want done for rocky, unless proven otherwise; 
#./disable_user_namespaces.sh

# Print final summary (this will also be triggered by EXIT trap)
print_build_summary
