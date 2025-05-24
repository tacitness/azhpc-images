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

# Use find command to locate the actual RPM files that were built
LIBNCCL_RPM=$(find ./build/pkg/rpm/x86_64/ -name "libnccl-${NCCL_VERSION}+cuda*.x86_64.rpm" -type f)
LIBNCCL_DEVEL_RPM=$(find ./build/pkg/rpm/x86_64/ -name "libnccl-devel-${NCCL_VERSION}+cuda*.x86_64.rpm" -type f)
LIBNCCL_STATIC_RPM=$(find ./build/pkg/rpm/x86_64/ -name "libnccl-static-${NCCL_VERSION}+cuda*.x86_64.rpm" -type f)

# Check if NCCL is already installed and get version
INSTALLED_NCCL_VERSION=$(rpm -q libnccl --queryformat '%{VERSION}' 2>/dev/null || echo "")

# Try to extract CUDA version - might not always be present in version string
INSTALLED_NCCL_CUDA_VERSION=""
if [[ "$INSTALLED_NCCL_VERSION" == *"cuda"* ]]; then
    INSTALLED_NCCL_CUDA_VERSION=$(echo "$INSTALLED_NCCL_VERSION" | grep -oP '(?<=cuda)[\d\.]+' || echo "")
fi

echo "Found built NCCL RPMs:"
echo "  $LIBNCCL_RPM"
echo "  $LIBNCCL_DEVEL_RPM"
echo "  $LIBNCCL_STATIC_RPM"

if [ -n "$INSTALLED_NCCL_VERSION" ]; then
    echo "Detected installed NCCL: $INSTALLED_NCCL_VERSION (CUDA $INSTALLED_NCCL_CUDA_VERSION)"
    
    # Extract version of the built package for comparison
    BUILT_NCCL_VERSION=$(echo "$LIBNCCL_RPM" | grep -oP '(?<=libnccl-)[^+]+' || echo "")
    BUILT_NCCL_CUDA_VERSION=$(echo "$LIBNCCL_RPM" | grep -oP '(?<=cuda)[\d\.]+' || echo "")
    echo "Built NCCL package: $BUILT_NCCL_VERSION (CUDA $BUILT_NCCL_CUDA_VERSION)"
    
    # Skip installation if newer version is already installed
    if rpm --quiet -q libnccl && [[ "$INSTALLED_NCCL_VERSION" > "$BUILT_NCCL_VERSION" ]]; then
        echo "A newer version of NCCL is already installed. Skipping installation."
    else
        echo "Installing built NCCL packages with --force flag to handle potential conflicts..."
        if [ -n "$LIBNCCL_RPM" ]; then
            rpm -i --force "$LIBNCCL_RPM" || echo "Warning: Failed to install $LIBNCCL_RPM, continuing anyway"
        fi
        if [ -n "$LIBNCCL_DEVEL_RPM" ]; then
            rpm -i --force "$LIBNCCL_DEVEL_RPM" || echo "Warning: Failed to install $LIBNCCL_DEVEL_RPM, continuing anyway"
        fi
        if [ -n "$LIBNCCL_STATIC_RPM" ]; then
            rpm -i --force "$LIBNCCL_STATIC_RPM" || echo "Warning: Failed to install $LIBNCCL_STATIC_RPM, continuing anyway"
        fi
    fi
else
    # No NCCL installed, proceed with normal installation
    echo "No existing NCCL installation detected. Installing packages..."
    if [ -n "$LIBNCCL_RPM" ]; then
        echo "Installing $LIBNCCL_RPM"
        rpm -i "$LIBNCCL_RPM"
    else
        echo "Warning: Could not find libnccl RPM"
        # List available RPMs for debugging
        find ./build/pkg/rpm/x86_64/ -type f
    fi

    if [ -n "$LIBNCCL_DEVEL_RPM" ]; then
        echo "Installing $LIBNCCL_DEVEL_RPM"
        rpm -i "$LIBNCCL_DEVEL_RPM"
    else
        echo "Warning: Could not find libnccl-devel RPM"
    fi

    if [ -n "$LIBNCCL_STATIC_RPM" ]; then
        echo "Installing $LIBNCCL_STATIC_RPM"
        rpm -i "$LIBNCCL_STATIC_RPM"
    else
        echo "Warning: Could not find libnccl-static RPM"
    fi
fi

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

echo "NCCL installation completed successfully"
exit 0
