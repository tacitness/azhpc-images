#!/bin/bash
set -ex

source /mnt/azhpc-images/rocky/rocky-8.x/rocky-8.10-hpc/set_properties.sh
source /mnt/azhpc-images/common/utilities.sh

pmix_metadata=$(get_component_config "pmix")
PMIX_VERSION=$(jq -r '.pmix."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)
REPO_DIR="$ROCKY_COMMON_DIR/../rocky-8.x/common"
INSTALL_PREFIX=/opt

cp ${REPO_DIR}/slurmel8.repo /etc/yum.repos.d/slurm.repo

## This package is pre-installed in all hpc images used by cyclecloud, but if customer wants to
## build an image from generic marketplace images then this package sets up the right gpg keys for PMC.
if [ ! -e /etc/yum.repos.d/microsoft-prod.repo ];then
   curl -sSL -O https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
   rpm -i packages-microsoft-prod.rpm
   rm packages-microsoft-prod.rpm
fi

crb enable
#yum -y install pmix-${PMIX_VERSION}.el8 pmix-devel-${PMIX_VERSION}.el8 munge-devel

# Build and install PMIx version 4.2.9 manually
pushd /opt/
wget -L https://github.com/openpmix/openpmix/releases/download/v4.2.9/pmix-4.2.9.tar.gz -O pmix-4.2.9.tar.gz
tar -xzf pmix-4.2.9.tar.gz
cd pmix-4.2.9

# Disable building docs by inserting AM_CONDITIONALs that force false
#sed -i '1im4_define([PMIX_VAR_SCOPE_PUSH], [])' configure.ac
#sed -i '1im4_define([PMIX_VAR_SCOPE_POP], [])' configure.ac
#sed -i '1im4_define([OAC_LOG_MSG], [])' configure.ac
#sed -i '1im4_define([OAC_LOG_MSG_NOPREFIX], [])' configure.ac
#perl -pi -e 's/^(AC_INIT\(\[.*\]\))/\1\nAM_CONDITIONAL([PMIX_BUILD_DOCS], [false])\nAM_CONDITIONAL([PMIX_INSTALL_DOCS], [false])/' configure.ac

sudo dnf install -y python3-sphinx python3-sphinx_rtd_theme

# Run autogen to regenerate configure script
#./autogen.pl
./configure --prefix=${INSTALL_PREFIX}/pmix/4.2.9

make -j$(nproc)
sudo make all install
popd

$COMMON_DIR/write_component_version.sh "PMIX" ${PMIX_VERSION}
