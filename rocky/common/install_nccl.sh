#!/bin/bash
set -ex

# Get version information first
NCCL_VERSION=$(jq -r '.nccl."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)
NCCL_RDMA_SHARP_COMMIT=$(jq -r '.nccl."'"$DISTRIBUTION"'".rdmasharpplugins.commit' <<< $COMPONENT_VERSIONS)
CUDA_DRIVER_VERSION=$(jq -r '.cuda."'"$DISTRIBUTION"'".driver.version' <<< $COMPONENT_VERSIONS)
CUDA_VERSION="${CUDA_DRIVER_VERSION//-/.}"

# Install NCCL
yum install -y rpm-build rpmdevtools
TARBALL="v${NCCL_VERSION}.tar.gz"
NCCL_DOWNLOAD_URL=https://github.com/NVIDIA/nccl/archive/refs/tags/${TARBALL}
pushd /tmp
wget ${NCCL_DOWNLOAD_URL}
tar -xvf ${TARBALL}

pushd nccl-${NCCL_VERSION}
make -j src.build
make pkg.redhat.build
rpm -i ./build/pkg/rpm/x86_64/libnccl-${NCCL_VERSION}+cuda${CUDA_VERSION}.x86_64.rpm
rpm -i ./build/pkg/rpm/x86_64/libnccl-devel-${NCCL_VERSION}+cuda${CUDA_VERSION}.x86_64.rpm
rpm -i ./build/pkg/rpm/x86_64/libnccl-static-${NCCL_VERSION}+cuda${CUDA_VERSION}.x86_64.rpm

# Add libnccl* to the exclude list
if grep -q "^exclude=" /etc/dnf/dnf.conf; then
    # Append to existing exclude line
    sed -i "/^exclude=/ s/$/ libnccl*/" /etc/dnf/dnf.conf
else
    # Create new exclude line
    echo "exclude=libnccl*" >> /etc/dnf/dnf.conf
fi
popd

# Install the nccl rdma sharp plugin
mkdir -p /usr/local/nccl-rdma-sharp-plugins
git clone https://github.com/Mellanox/nccl-rdma-sharp-plugins.git
pushd nccl-rdma-sharp-plugins
git checkout ${NCCL_RDMA_SHARP_COMMIT}
./autogen.sh
./configure --prefix=/usr/local/nccl-rdma-sharp-plugins --with-cuda=/usr/local/cuda
make
make install
popd

# Build the nccl tests
source /etc/profile.d/modules.sh
module load mpi/hpcx
git clone https://github.com/NVIDIA/nccl-tests.git
pushd nccl-tests
make MPI=1 MPI_HOME=${HPCX_MPI_DIR} CUDA_HOME=/usr/local/cuda
popd

# Handle idempotent installation of NCCL tests
if [ -d "/opt/nccl-tests" ]; then
    echo "NCCL tests directory already exists at /opt/nccl-tests, skipping move"
else
    echo "Moving nccl-tests to /opt/"
    mv nccl-tests /opt/.
fi
module unload mpi/hpcx
$COMMON_DIR/write_component_version.sh "NCCL" ${NCCL_VERSION}

# Remove installation files
rm -rf /tmp/${TARBALL}
rm -rf /tmp/nccl-${NCCL_VERSION}
rm -rf /tmp/nccl-rdma-sharp-plugins
popd  # Return from /tmp
