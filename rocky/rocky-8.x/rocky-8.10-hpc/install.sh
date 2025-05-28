#!/bin/bash
set -ex

# Clean up DNF config at the beginning - thorough approach to fix corrupt configuration
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

# Complete Intel MPI cleanup before install
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

# Clean up NCCL related files and directories before install
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

# Clear non-redistributable GPU software - ONLY for public distribution
# When SKIP_NVIDIA_COMPONENTS=1:
#   - INSTALLED: NVIDIA Datacenter Driver (redistributable)
#   - SKIPPED: CUDA Toolkit, NVIDIA DCGM, NVIDIA Fabric Manager, GDRCopy, GPUDirect RDMA
SKIP_NVIDIA_COMPONENTS=1

# install pre-requisites
./install_prerequisites.sh

# set properties
source ./set_properties.sh

# install utils
./install_utils.sh

# install Lustre client
$ROCKY_COMMON_DIR/install_lustre_client.sh "8"

# install compilers
./install_gcc.sh

# install mellanox ofed
./install_mellanoxofed.sh

# install PMIX
$ROCKY_COMMON_DIR/../rocky-8.x/common/install_pmix.sh

# install mpi libraries
echo "DEBUG: MPIS: Entering ./install_mpis.sh"
env | colrm 180
pwd
./install_mpis.sh

# Install NVIDIA components
if [ "$SKIP_NVIDIA_COMPONENTS" = "1" ]; then
    echo "Installing only redistributable NVIDIA driver"
    # Install only the NVIDIA driver (redistributable)
    ./install_nvidia_driver_only.sh
else
    # Install all NVIDIA components including non-redistributable ones
    ./install_nvidiagpudriver.sh
fi

# install AMD tuned libraries
./install_amd_libs.sh

# install Intel libraries
./install_intel_libs.sh

# cleanup downloaded tarballs - clear some space
rm -rf *.tgz *.bz2 *.tbz *.tar.gz *.run *.deb *_offline.sh
rm -rf /tmp/MLNX_OFED_LINUX* /tmp/*conf*
rm -rf /var/intel/ /var/cache/*
#rm -Rf -- */

# Install NCCL (redistributable)
if [ "$SKIP_NVIDIA_COMPONENTS" = "1" ]; then
    echo "Installing redistributable version of NCCL"
    ./install_nccl_redist.sh
else
    echo "Installing full NCCL with CUDA dependencies"
    ./install_nccl.sh
fi

# NVIDIA container components (non-redistributable)
if [ "$SKIP_NVIDIA_COMPONENTS" != "1" ]; then
    # Install NVIDIA docker container
    $COMMON_DIR/../rocky/rocky-8.x/common/install_docker.sh

    # Install DCGM
    ./install_dcgm.sh
else
    echo "Skipping non-redistributable NVIDIA components (Docker container toolkit, DCGM)"
fi

# optimizations
./hpc-tuning.sh

# install persistent rdma naming
$COMMON_DIR/install_azure_persistent_rdma_naming.sh

# add udev rule
$COMMON_DIR/../rocky/common/add-udev-rules.sh

# add interface rules
$COMMON_DIR/../rocky/common/network-config.sh

# install diagnostic script
$COMMON_DIR/install_hpcdiag.sh

#install monitoring tools
$COMMON_DIR/../rocky/common/install_monitoring_tools.sh

# install Azure/NHC Health Checks
$COMMON_DIR/install_health_checks.sh

# copy test file
$COMMON_DIR/copy_test_file.sh

# disable cloud-init
$ROCKY_COMMON_DIR/disable_cloudinit.sh

# SKU Customization
$COMMON_DIR/setup_sku_customizations.sh

# clear history
# Uncomment the line below if you are running this on a VM
$COMMON_DIR/clear_history.sh

# Called out as alma only patch, disabling namespaces is not likely what we want done for rocky, unless proven otherwise; 
#./disable_user_namespaces.sh
