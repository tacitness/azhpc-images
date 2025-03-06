#!/bin/bash
set -ex

mofed_metadata=$(jq -r '.mofed."'"$DISTRIBUTION"'"' <<< $COMPONENT_VERSIONS)
MOFED_VERSION=$(jq -r '.version' <<< $mofed_metadata)
MOFED_SHA256=$(jq -r '.sha256' <<< $mofed_metadata)
MOFED_DISTRO=${DISTRIBUTION/rocky/rhel}
TARBALL="MLNX_OFED_LINUX-$MOFED_VERSION-$MOFED_DISTRO-x86_64.tgz"
MLNX_OFED_DOWNLOAD_URL=https://content.mellanox.com/ofed/MLNX_OFED-${MOFED_VERSION}/$TARBALL
MOFED_FOLDER=$(basename ${MLNX_OFED_DOWNLOAD_URL} .tgz)

#$COMMON_DIR/download_and_verify.sh $MLNX_OFED_DOWNLOAD_URL $MOFED_SHA256
#tar zxvf ${TARBALL}

## RPM Path 
cp files/mellanox_mlnx_ofed.repo /etc/yum.repos.d/
perl -ni -e 'print unless /exclude/' /etc/yum.conf
perl -ni -e 'print unless /exclude/' /etc/dnf/dnf.conf

## kernel-source
pkgs="ofed-scripts.x86_64
mlnx-ofed-all 
mlnx-tools 
mlnx-ethtool 
mlnx-ofed-hpc 
mlnx-fw-updater 
knem
mlnx-tools.x86_64
mlnx-ofa_kernel.x86_64
kmod-mlnx-ofa_kernel.x86_64
mlnx-ofa_kernel-devel.x86_64
mlnx-ofa_kernel-source.x86_64
mlnx-ofa_kernel-devel.x86_64
mlnx-ofa_kernel-source.x86_64
knem.x86_64
kmod-knem.x86_64
ucx-knem.x86_64
xpmem.x86_64
kmod-xpmem.x86_64
libxpmem.x86_64
libxpmem-devel.x86_64
ucx-xpmem.x86_64
kmod-kernel-mft-mlnx.x86_64
kmod-iser.x86_64
kmod-isert.x86_64
socnetv.x86_64
kmod-srp.x86_64
srp_daemon.x86_64
uhd-tools.x86_64
kmod-isert.x86_64
kmod-mlnx-nfsrdma.x86_64
kmod-mlnx-nvme.x86_64"

$COMMON_DIR/download_and_verify.sh $MLNX_OFED_DOWNLOAD_URL $MOFED_SHA256
tar zxvf ${TARBALL}

## RPM Path 
cp files/mellanox_mlnx_ofed.repo /etc/yum.repos.d/
perl -ni -e 'print unless /exclude/' /etc/yum.conf
perl -ni -e 'print unless /exclude/' /etc/dnf/dnf.conf

# If using rpm path uncomment: 
#dnf install -y $pkgs

KERNEL=( $(rpm -q kernel | sed 's/kernel\-//g') )
KERNEL=${KERNEL[-1]}

# If using rpm path comment out: 
echo ./${MOFED_FOLDER}/mlnxofedinstall --kernel $KERNEL --kernel-sources /usr/src/kernels/${KERNEL} --add-kernel-support --skip-repo --skip-unsupported-devices-check --without-fw-update --distro ${DISTRIBUTION/rocky/rhel}
exit

# Issue: Module mlx5_ib belong to a kernel which is not a part of MLNX
# Resolution: set FORCE=1/ force-restart /etc/init.d/openibd 
# This causes openibd to ignore the kernel difference but relies on weak-updates
# Restarting openibd
/etc/init.d/openibd force-restart
$COMMON_DIR/write_component_version.sh "MOFED" $MOFED_VERSION

# exclude opensm from updates
sed -i "$ s/$/ opensm*/" /etc/dnf/dnf.conf

# cleanup downloaded files
#rm -rf *.tgz
#rm -rf -- */
