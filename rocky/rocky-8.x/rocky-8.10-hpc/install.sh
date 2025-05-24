#!/bin/bash
set -ex

# Clean up DNF config at the beginning - simple approach to remove all exclude lines
if [ -f "/etc/dnf/dnf.conf" ]; then
    echo "Cleaning up DNF configuration excludes..."
    # Remove all exclude lines - they will be added back by individual scripts
    sed -i '/^exclude=/d' /etc/dnf/dnf.conf
    echo "DNF configuration exclude lines removed"
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
  rm -rf hpcx-v2.19-gcc-mlnx_ofed-redhat8-cuda12-x86_64* MLNX_OFED_LINUX-24.10-1.1.4.0-rhel8.10-x86_64* mvapich2* openmpi* ucx* 

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

# Call the cleanup function before installing Intel MPI
intel_cleanup

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

# install nvidia gpu driver
./install_nvidiagpudriver.sh

# install AMD tuned libraries
./install_amd_libs.sh

# install Intel libraries
./install_intel_libs.sh

# cleanup downloaded tarballs - clear some space
rm -rf *.tgz *.bz2 *.tbz *.tar.gz *.run *.deb *_offline.sh
rm -rf /tmp/MLNX_OFED_LINUX* /tmp/*conf*
rm -rf /var/intel/ /var/cache/*
#rm -Rf -- */

# Install NCCL
./install_nccl.sh

# Install NVIDIA docker container
$COMMON_DIR/../rocky/rocky-8.x/common/install_docker.sh

# Install DCGM
./install_dcgm.sh

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

# add a security patch of CVE issue for AlmaLinux 8.7 only
./disable_user_namespaces.sh
