#!/bin/bash
set -ex

# Set the driver versions
cuda_metadata=$(jq -r '.cuda."'"$DISTRIBUTION"'"' <<< $COMPONENT_VERSIONS)
CUDA_DRIVER_VERSION=$(jq -r '.driver.version' <<< $cuda_metadata)
CUDA_DRIVER_DISTRIBUTION=$(jq -r '.driver.distribution' <<< $cuda_metadata)
CUDA_SAMPLES_VERSION=$(jq -r '.samples.version' <<< $cuda_metadata)

# Install Cuda
dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_DRIVER_DISTRIBUTION}/x86_64/cuda-${CUDA_DRIVER_DISTRIBUTION}.repo
dnf clean expire-cache -y
dnf install cuda-toolkit-${CUDA_DRIVER_VERSION} -y
echo 'export PATH=$PATH:/usr/local/cuda/bin' | tee -a /etc/bash.bashrc
echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64' | tee -a /etc/bash.bashrc
$COMMON_DIR/write_component_version.sh "CUDA" ${CUDA_DRIVER_VERSION}

# Download CUDA samples
# Normalize CUDA version for GitHub tag (strip minor version and ensure format v12.2) 
CUDA_SAMPLES_TAG_VERSION=$(echo "${CUDA_SAMPLES_VERSION}" | sed 's/-/\./g' | cut -d'.' -f1,2)
CUDA_MAJOR_VERSION=$(echo "${CUDA_SAMPLES_TAG_VERSION}" | cut -d'.' -f1)
TARBALL="v${CUDA_SAMPLES_TAG_VERSION}.tar.gz"
CUDA_SAMPLES_DOWNLOAD_URL=https://github.com/NVIDIA/cuda-samples/archive/refs/tags/${TARBALL}
echo "Attempting to download CUDA samples from ${CUDA_SAMPLES_DOWNLOAD_URL}"
wget ${CUDA_SAMPLES_DOWNLOAD_URL} || {
    echo "Failed to download CUDA samples with tag v${CUDA_SAMPLES_TAG_VERSION}"
    # Try a generic fallback to just major version (e.g., v12)
    echo "Trying fallback to v${CUDA_MAJOR_VERSION} tag..."
    TARBALL="v${CUDA_MAJOR_VERSION}.tar.gz"
    CUDA_SAMPLES_DOWNLOAD_URL=https://github.com/NVIDIA/cuda-samples/archive/refs/tags/${TARBALL}
    wget ${CUDA_SAMPLES_DOWNLOAD_URL} || {
        echo "Failed with v${CUDA_MAJOR_VERSION} too, falling back to v12.2 which is known to exist"
        TARBALL="v12.2.tar.gz"
        CUDA_SAMPLES_DOWNLOAD_URL=https://github.com/NVIDIA/cuda-samples/archive/refs/tags/${TARBALL}
        wget ${CUDA_SAMPLES_DOWNLOAD_URL}
    }
}
tar -xvf ${TARBALL}
# Extract the actual version from the extracted directory name
CUDA_SAMPLES_DIR=$(find . -maxdepth 1 -type d -name "cuda-samples-*" | head -1)
CUDA_SAMPLES_EXTRACTED_VERSION=$(basename ${CUDA_SAMPLES_DIR} | sed 's/cuda-samples-//')
echo "Using CUDA samples version: ${CUDA_SAMPLES_EXTRACTED_VERSION}"
pushd ${CUDA_SAMPLES_DIR}
make -j $(nproc)

# Handle idempotent installation of CUDA samples
if [ -d "/usr/local/cuda-${CUDA_DRIVER_VERSION}/samples" ]; then
    echo "CUDA samples directory already exists at /usr/local/cuda-${CUDA_DRIVER_VERSION}/samples, skipping move"
else
    echo "Moving CUDA samples to /usr/local/cuda-${CUDA_DRIVER_VERSION}/samples"
    mkdir -p /usr/local/cuda-${CUDA_DRIVER_VERSION}
    mv -vT ./Samples /usr/local/cuda-${CUDA_DRIVER_VERSION}/samples
fi
popd

# Install NVIDIA driver
nvidia_driver_metadata=$(jq -r '.nvidia."'"$DISTRIBUTION"'".driver' <<< $COMPONENT_VERSIONS)
NVIDIA_DRIVER_VERSION=$(jq -r '.version' <<< $nvidia_driver_metadata)
NVIDIA_DRIVER_SHA256=$(jq -r '.sha256' <<< $nvidia_driver_metadata)
NVIDIA_DRIVER_URL=https://us.download.nvidia.com/tesla/${NVIDIA_DRIVER_VERSION}/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run

$COMMON_DIR/download_and_verify.sh $NVIDIA_DRIVER_URL ${NVIDIA_DRIVER_SHA256}
bash NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run --silent --dkms
dkms install --no-depmod -m nvidia -v ${NVIDIA_DRIVER_VERSION} -k `uname -r` --force
$COMMON_DIR/write_component_version.sh "NVIDIA" ${NVIDIA_DRIVER_VERSION}

# load the nvidia-peermem coming as a part of NVIDIA GPU driver
# Reference - https://download.nvidia.com/XFree86/Linux-x86_64/510.85.02/README/nvidia-peermem.html
if ! modprobe nvidia-peermem; then echo "Failed to install module nvidia-peermem; continuing build anyway ... "; fi
# verify if loaded
if ! lsmod | grep nvidia_peermem; then echo "nvidia-peermem not loaded ... continuing build anyway ... "; fi

# Install GDRCopy
GDRCOPY_VERSION=$(jq -r '.gdrcopy."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)
TARBALL="v${GDRCOPY_VERSION}.tar.gz"
GDRCOPY_DOWNLOAD_URL=https://github.com/NVIDIA/gdrcopy/archive/refs/tags/${TARBALL}
wget $GDRCOPY_DOWNLOAD_URL
tar -xvf $TARBALL

pushd gdrcopy-${GDRCOPY_VERSION}/packages/
CUDA=/usr/local/cuda ./build-rpm-packages.sh

# Check if GDRCopy is already installed with a newer version
echo "Checking existing GDRCopy installations..."
INSTALLED_VERSION=$(rpm -q --queryformat '%{VERSION}' gdrcopy-kmod 2>/dev/null || echo "not_installed")
echo "Installed GDRCopy version: ${INSTALLED_VERSION}"
echo "Version to install: ${GDRCOPY_VERSION}"

# Function to compare versions
version_greater_equal() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
    return $?
}

# Install packages with appropriate flags
install_rpm() {
    local package=$1
    local force_flag=$2
    
    if [ "$force_flag" = "force" ]; then
        echo "Force installing ${package}"
        rpm -Uvh --force ${package}
    else
        echo "Installing ${package}"
        rpm -Uvh ${package} || echo "Warning: Failed to install ${package}, may be already installed or newer version present"
    fi
}

# Install GDRCopy packages, handling the case when a newer version exists
if [ "$INSTALLED_VERSION" = "not_installed" ] || ! version_greater_equal "$INSTALLED_VERSION" "${GDRCOPY_VERSION}"; then
    echo "Installing GDRCopy ${GDRCOPY_VERSION}..."
    # Use regular RPM install
    install_rpm gdrcopy-kmod-${GDRCOPY_VERSION}-1dkms.noarch.el8.rpm
    install_rpm gdrcopy-${GDRCOPY_VERSION}-1.x86_64.el8.rpm
    install_rpm gdrcopy-devel-${GDRCOPY_VERSION}-1.noarch.el8.rpm
else
    echo "Newer version of GDRCopy (${INSTALLED_VERSION}) is already installed, skipping installation of version ${GDRCOPY_VERSION}"
fi

# Add to exclude list from updates regardless
sed -i "$ s/$/ gdrcopy*/" /etc/dnf/dnf.conf
popd

$COMMON_DIR/write_component_version.sh "GDRCOPY" ${GDRCOPY_VERSION}

# Set NVIDIA fabricmanager version
nvidia_fabricmanager_metadata=$(jq -r '.nvidia."'"$DISTRIBUTION"'".fabricmanager' <<< $COMPONENT_VERSIONS)
NVIDIA_FABRICMANAGER_DISTRIBUTION=$(jq -r '.distribution' <<< $nvidia_fabricmanager_metadata)
NVIDIA_FABRICMANAGER_VERSION=$(jq -r '.version' <<< $nvidia_fabricmanager_metadata)
NVIDIA_FABRICMANAGER_SHA256=$(jq -r '.sha256' <<< $nvidia_fabricmanager_metadata)

# Install Fabric Manager
NVIDIA_FABRIC_MNGR_URL=http://developer.download.nvidia.com/compute/cuda/repos/${NVIDIA_FABRICMANAGER_DISTRIBUTION}/x86_64/nvidia-fabric-manager-${NVIDIA_FABRICMANAGER_VERSION}.x86_64.rpm
$COMMON_DIR/download_and_verify.sh ${NVIDIA_FABRIC_MNGR_URL} ${NVIDIA_FABRICMANAGER_SHA256}
yum install -y ./nvidia-fabric-manager-${NVIDIA_FABRICMANAGER_VERSION}.x86_64.rpm
sed -i "$ s/$/ nvidia-fabric-manager/" /etc/dnf/dnf.conf
$COMMON_DIR/write_component_version.sh "NVIDIA_FABRIC_MANAGER" ${NVIDIA_FABRICMANAGER_VERSION}

# cleanup downloaded files
rm -rf *.run *tar.gz *.rpm
rm -rf -- */
