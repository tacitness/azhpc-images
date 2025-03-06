#!/bin/bash
set -ex

# Load gcc 9.2.1
source scl_source enable gcc-toolset-9
set CC=/opt/rh/gcc-toolset-9/root/usr/bin/gcc
set GCC=/opt/rh/gcc-toolset-9/root/usr/bin/gcc


INSTALL_PREFIX=/opt

PMIX_VERSION=$(jq -r '.pmix."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)
PMIX_PATH=${INSTALL_PREFIX}/pmix/${PMIX_VERSION:0:-2}

# Install HPC-x
hpcx_metadata=$(jq -r '.hpcx."'"$DISTRIBUTION"'"' <<< $COMPONENT_VERSIONS)
HPCX_VERSION=$(jq -r '.version' <<< $hpcx_metadata)
HPCX_SHA256=$(jq -r '.sha256' <<< $hpcx_metadata)
HPCX_DOWNLOAD_URL=$(jq -r '.url' <<< $hpcx_metadata)
TARBALL=$(basename $HPCX_DOWNLOAD_URL)
HPCX_FOLDER=$(basename $HPCX_DOWNLOAD_URL .tbz)

$COMMON_DIR/download_and_verify.sh $HPCX_DOWNLOAD_URL $HPCX_SHA256
tar -xvf ${TARBALL}

sed -i "s/\/build-result\//\/opt\//" ${HPCX_FOLDER}/hcoll/lib/pkgconfig/hcoll.pc
if ! mv ${HPCX_FOLDER} ${INSTALL_PREFIX}; then rm -rf ${INSTALL_PREFIX}/${HPCX_FOLDER}; mv ${HPCX_FOLDER} ${INSTALL_PREFIX}; fi
HPCX_PATH=${INSTALL_PREFIX}/${HPCX_FOLDER}
$COMMON_DIR/write_component_version.sh "HPCX" $HPCX_VERSION

# rebuild HPCX with PMIx
${HPCX_PATH}/utils/hpcx_rebuild.sh --with-hcoll --ompi-extra-config "--with-pmix=${PMIX_PATH} --enable-orterun-prefix-by-default"
cp -r ${HPCX_PATH}/ompi/tests ${HPCX_PATH}/hpcx-rebuild

# exclude ucx from updates
sed -i "$ s/$/ ucx*/" /etc/dnf/dnf.conf

# Setup module files for MPIs
MODULE_FILES_DIRECTORY=/usr/share/Modules/modulefiles/mpi
mkdir -p ${MODULE_FILES_DIRECTORY}

# HPC-X
cat << EOF >> ${MODULE_FILES_DIRECTORY}/hpcx-${HPCX_VERSION}
#%Module 1.0
#
#  HPCx ${HPCX_VERSION}
#
conflict        mpi
module load ${HPCX_PATH}/modulefiles/hpcx
EOF

# HPC-X with PMIX
cat << EOF >> ${MODULE_FILES_DIRECTORY}/hpcx-pmix-${HPCX_VERSION}
#%Module 1.0
#
#  HPCx ${HPCX_VERSION}
#
conflict        mpi
module load ${HPCX_PATH}/modulefiles/hpcx-rebuild
EOF

# Create symlinks for modulefiles
ln -s ${MODULE_FILES_DIRECTORY}/hpcx-${HPCX_VERSION} ${MODULE_FILES_DIRECTORY}/hpcx
ln -s ${MODULE_FILES_DIRECTORY}/hpcx-pmix-${HPCX_VERSION} ${MODULE_FILES_DIRECTORY}/hpcx-pmix

# Install platform independent MPIs
$ROCKY_COMMON_DIR/install_mpis.sh ${HPCX_PATH}

# cleanup downloaded tarball for HPC-x
rm -rf *.tbz 
