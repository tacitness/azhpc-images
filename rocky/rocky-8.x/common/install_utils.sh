#!/bin/bash
set -ex

# Install Python 3.8
yum install -y python3.8
alternatives --set python3 /usr/bin/python3.8
alternatives --set python /usr/bin/python3.8

# install pssh
yum install -y epel-release
crb enable
yum install -y pssh

# Install pre-reqs and development tools
yum groupinstall -y "Development Tools"
yum install -y numactl \
    numactl-devel \
    libxml2-devel \
    byacc \
    python3-devel \
    python3-setuptools \
    gtk2 \
    atk \
    cairo \
    tcl \
    tk \
    m4 \
    glibc-devel \
    libudev-devel \
    binutils \
    binutils-devel \
    selinux-policy-devel \
    nfs-utils \
    fuse-libs \
    libpciaccess \
    cmake \
    libnl3-devel \
    libsecret \
    rpm-build \
    make \
    check \
    check-devel \
    lsof \
    tcsh \
    gcc-gfortran \
    perl \
    environment-modules \
    dkms \
    subunit \
    subunit-devel \
    jq \
    jq-devel

## Install Ansys Required Libraries:
sudo dnf -y install alsa-lib at-spi2-atk at-spi2-core atk avahi-libs cairo cairo-gobject cups-libs dbus-libs expat fribidi gdk-pixbuf2 glib2 glibc glibc-devel gnutls graphite2 gtk3 gzip harfbuzz keyutils-libs krb5-libs libXcomposite libXcursor libXdamage libXfixes libXi libXinerama libXrandr libXrender libblkid libcap libcom_err libdatrie libdrm libepoxy libgcrypt libgpg-error libidn2 libjpeg-turbo libmount libnsl libselinux libtasn1 libthai libunistring libuuid libwayland-client libwayland-cursor libwayland-egl libwayland-server libxcb libxcrypt libxkbcommon mesa-libgbm nettle nspr nss nss-util p11-kit pango pcre2 redhat-lsb-core systemd-libs tar which xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi audit-libs brotli bzip2-libs cyrus-sasl-lib freetype gmp gstreamer1 gstreamer1-plugins-base gtk2 hwloc-libs jbigkit-libs libX11 libXScrnSaver libXau libXdmcp libXext libXft libXtst libXxf86vm libcap-ng libfontenc libgcc libglvnd libglvnd-egl libglvnd-glx libibverbs libnghttp2 libomp libpng libpsl libssh libstdc++ libtiff libxkbcommon-x11 libxml2 libxshmfence libxslt nss-softokn openldap orc pam pciutils-libs perl-devel pixman xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm xz-libs zlib brotli cyrus-sasl-lib elfutils-libelf fontconfig gmp gstreamer1 gstreamer1-plugins-base gtk2 hwloc-libs jbigkit-libs libXft libXtst libXxf86vm libgcc libglvnd libglvnd-egl libibverbs libicu50 libnghttp2 libnotify libomp libpng12 libpsl libssh libstdc++ libtiff libxml2 libxshmfence libxslt libzstd lz4-libs ncurses-libs nss-softokn nss-softokn-freebl numactl-libs openldap openssl-libs orc pcre perl-devel pixman xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm xterm
yum -y --allowerasing install libcurl-minimal libcurl-devel
yum -y install glibc.i686

## Install ucx:
#yum -y localinstall $COMMON_DIR/rpmbuild/RPMS/x86_64/*.rpm

## Failed to build MLNX_OFED_LINUX for 4.18.0-513.24.1.el8_9.x86_64: 
yum install -y pciutils

## Additional Utilities *WANTED* but not needed, see CIQ <-> Ansys email Thread: 
dnf install -y expect flex-devel giflib mesa-libEGL-devel mesa-libGL-devel mesa-libGLU mesa-libGLw-devel mesa-libOSMesa-devel mesa-libgbm-devel motif motif-devel redhat-lsb blas compat-libgfortran-48 fftw-libs flac-libs freeglut gsm gtk2 icu lapack libICE libSM libX11 libXau libXext libXt libXxf86vm libasyncns libgcc libglvnd-glx libnsl2 libpng15 libsndfile libstdc++ libstdc++-devel libtiff-devel libunwind libuuid libxcb mesa-dri-drivers mesa-filesystem minizip openal-soft proj-devel qt5-qtmultimedia qt5-qtscript telnet tigervnc-server tinyxml xerces-c xorg-x11-fonts-ISO8859-1-75dpi xorg-x11-fonts-cyrillic

# Disable dependencies on kernel core
echo "exclude=kernel* kmod*" | tee -a /etc/dnf/dnf.conf
echo "exclude=kernel* kmod*" | tee -a /etc/yum.conf
sed -i "$ s/$/ shim*/" /etc/dnf/dnf.conf
sed -i "$ s/$/ grub2*/" /etc/dnf/dnf.conf

$COMMON_DIR/install_azcopy.sh

# copy kvp client file
$COMMON_DIR/copy_kvp_client.sh
