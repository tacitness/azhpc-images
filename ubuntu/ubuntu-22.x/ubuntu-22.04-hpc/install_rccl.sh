#!/bin/bash
set -ex

#update CMAKE
pushd /tmp
CMAKE_VER="3.30.6"
wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}-linux-x86_64.tar.gz
tar xzf cmake-${CMAKE_VER}-linux-x86_64.tar.gz
pushd cmake-${CMAKE_VER}-linux-x86_64
pushd bin
sudo mv -f ccmake cmake cpack ctest /usr/local/bin
popd
sudo cp -r share/cmake-3.30 /usr/local/share/
popd
rm -rf cmake-${CMAKE_VER}-linux-x86_64*
hash -r

apt install libstdc++-12-dev
apt remove -y rccl
pushd ~
git clone https://github.com/rocm/rccl
popd
mkdir ~/rccl/build
pushd ~/rccl/build
CXX=/opt/rocm/bin/hipcc cmake -DCMAKE_PREFIX_PATH=/opt/rocm/ -DCMAKE_INSTALL_PREFIX=/opt/rccl ..
make -j
make install
popd

pushd ~

sysctl kernel.numa_balancing=0
echo "kernel.numa_balancing=0" | tee -a /etc/sysctl.conf


git clone https://github.com/ROCmSoftwarePlatform/rccl-tests
pushd ~/rccl-tests

source /opt/hpcx*/hpcx-init.sh
hpcx_load

HPCX="/opt/hpcx-v2.16-gcc-mlnx_ofed-ubuntu22.04-cuda12-gdrcopy2"
HPCX+="-nccl2.18-x86_64/ompi/"
RCCLLIB="/opt/rccl/lib/librccl.so"
RCCLDIR="/opt/rccl"


echo "gfx942" > target.lst
echo "gfx90a" >> target.lst

ROCM_TARGET_LST=$(pwd)/target.lst make MPI=1 \
        NCCL_HOME=$RCCLDIR CUSTOM_RCCL_LIB=$RCCLLIB

popd

DEST_TEST_DIR=/opt/rccl-tests
mkdir -p $DEST_TEST_DIR

cp -r ~/rccl-tests/build/* $DEST_TEST_DIR
rm -rf rccl-tests

git clone https://github.com/ROCm/rdma-perftest
mkdir /opt/rocm-perftest
pushd ~/rdma-perftest
./autogen.sh
./configure --enable-rocm --with-rocm=/opt/rocm --prefix=/opt/rocm-perftest/
make -j 32
make install

popd
