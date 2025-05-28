#!/bin/bash
set -ex

# This script installs NCCL in redistributable-only mode
# NCCL itself is open source and redistributable, but we need to handle CUDA dependencies

# Check if we're in redistributable-only mode
if [ "$SKIP_NVIDIA_COMPONENTS" = "1" ]; then
    echo "Installing NCCL in redistributable-only mode (without CUDA dependencies)"
    
    # Install basic NCCL from source - this is the open source library only
    # We'll need to modify some build parameters to avoid CUDA dependencies
    
    # Get version information
    NCCL_VERSION=$(jq -r '.nccl."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)
    NCCL_RDMA_SHARP_COMMIT=$(jq -r '.nccl."'"$DISTRIBUTION"'".rdmasharpplugins.commit' <<< $COMPONENT_VERSIONS)
    
    # Install NCCL
    yum install -y rpm-build rpmdevtools
    TARBALL="v${NCCL_VERSION}.tar.gz"
    NCCL_DOWNLOAD_URL=https://github.com/NVIDIA/nccl/archive/refs/tags/${TARBALL}
    pushd /tmp
    wget ${NCCL_DOWNLOAD_URL}
    tar -xvf ${TARBALL}
    
    pushd nccl-${NCCL_VERSION}
    # Build without CUDA
    make -j src.build CUDA_HOME=/usr || echo "Building without CUDA may show warnings"
    
    # Install to system directories
    mkdir -p /usr/local/include
    mkdir -p /usr/local/lib
    cp -a build/include/* /usr/local/include/
    cp -a build/lib/* /usr/local/lib/
    ldconfig
    
    popd
    
    # Install the nccl rdma sharp plugin - also open source
    mkdir -p /usr/local/nccl-rdma-sharp-plugins
    
    git clone https://github.com/Mellanox/nccl-rdma-sharp-plugins.git
    pushd nccl-rdma-sharp-plugins
    git checkout ${NCCL_RDMA_SHARP_COMMIT}
    ./autogen.sh
    ./configure --prefix=/usr/local/nccl-rdma-sharp-plugins
    make
    make install
    popd
    
    # Remove installation files
    rm -rf /tmp/${TARBALL}
    rm -rf /tmp/nccl-${NCCL_VERSION}
    rm -rf /tmp/nccl-rdma-sharp-plugins
    
    $COMMON_DIR/write_component_version.sh "NCCL" ${NCCL_VERSION}
    
    echo "NCCL installation (redistributable-only mode) completed"
else
    # Full installation with CUDA dependencies
    echo "Installing full NCCL with CUDA dependencies"
    $ROCKY_COMMON_DIR/install_nccl.sh
fi
