#!/usr/bin/bash   
sudo rpm -e jq-devel-1.6-7.el8.x86_64 jq-1.6-7.el8.x86_64
sudo rpm -e dkms-3.0.13-1.el8.noarch 
sudo rpm -e gcc-c++-8.5.0-22.el8_10.x86_64
sudo rpm -e cuda-nvcc-12-4-12.4.131-1.x86_64 cuda-compiler-12-4-12.4.1-1.x86_64 cuda-toolkit-12-4-12.4.1-1.x86_64
sudo dnf group remove -y "Development Tools" 
sudo rpm -e glibc-headers-2.28-251.el8_10.2.x86_64 libnl3-devel-3.7.0-1.el8.x86_64 rshim-2.0.19-0.gbf7f1f2.x86_64  rdma-core-devel-2307mlnx47-1.2401033.x86_64 rdma-core-devel-2307mlnx47-1.2401033.x86_64 libxcrypt-devel-4.1.1-6.el8.x86_64 glibc-devel-2.28-251.el8_10.2.x86_64 opensm-devel-5.18.0.MLNX20240128.3f266a48-0.1.2401033.x86_64 opensm-static-5.18.0.MLNX20240128.3f266a48-0.1.2401033.x86_64 hwloc-devel-2.2.0-3.el8.x86_64 glibc-devel-2.28-251.el8_10.2.x86_64 gcc-8.5.0-22.el8_10.x86_64 annobin-11.13-2.el8.x86_64 gcc-plugin-annobin-8.5.0-22.el8_10.x86_64 gcc-gfortran-8.5.0-22.el8_10.x86_64 libquadmath-devel-8.5.0-22.el8_10.x86_64 
sudo dnf remove -y glibc-headers libnl3-devel gcc libxml2-devel
sudo rpm -e kernel-headers-4.18.0-513.5.1.el8_9.x86_64 kernel-modules-extra-4.18.0-513.5.1.el8_9.x86_64 kernel-devel-4.18.0-513.5.1.el8_9.x86_64 kernel-rpm-macros-131-1.el8.noarch
sudo rm -rf kernel-{headers,modules-extra,devel}-*.rpm
sudo rm -rf /etc/yum.repos.d/microsoft-prod.repo
sudo rm -rf /var/cache/dnf/*
sudo rm -rf /opt/{hpcx-*,intel,knem-*,mellanox,mvapich2-*,nvidia,openmpi*,pmix}
sudo rm -rf /usr/share/Modules/modulefiles/mpi/hpcx
sudo rm -rf /usr/local/cuda-*
sudo rm -rf v12.4.tar.gz
sudo rm -rf hpcx-v2.18-gcc*
sudo rm -rf kvp_client.c
sudo rm -rf hpcx-v2.18-gcc-mlnx_ofed-redhat8-cuda12-x86_64.tbz
sudo rm -rf NVIDIA-Linux*
sudo rm -f MLNX_OFED_LINUX-24.01-0.3.3.1-rhel8.9-x86_64.tgz* kernel-rpm-macros-131-1.el8.noarch.rpm pssh-2.3.1-29.el8.noarch.rpm

sudo dnf clean all
