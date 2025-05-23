#!/bin/bash
# Ansys HPC Image Customization for Rocky 8.10

set -e

echo "=== Ansys HPC Image Customization Script ==="
echo "$(date)"

# Install required packages
PKG_INSTALL="cifs-utils dkms git htop jq kernel-devel kernel-headers nano nfs-utils ocl-icd-devel pciutils rsync tree wget zip"

# Full Ansys product package list
ANSYS_PKGS="brotli bzip2-libs cyrus-sasl-lib expat fontconfig freetype glib2 glibc glibc-devel gmp gnutls gzip keyutils-libs krb5-libs libICE libSM libX11 libX11-xcb libXau libXext libcom_err libcurl libffi libidn2 libjpeg-turbo libnghttp2 libnsl libnsl2 libpng libpsl libselinux libssh libtasn1 libunistring libuuid libxcb libxcrypt libxkbcommon libxkbcommon-x11 nettle openldap openssl-libs p11-kit pcre pcre2 tar which xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm xorg-x11-fonts-100dpi xorg-x11-fonts-75dpi zlib alsa-lib at-spi2-atk at-spi2-core atk avahi-libs cairo cairo-gobject cups-libs dbus-libs fribidi gdk-pixbuf2 graphite2 gtk3 harfbuzz hwloc-libs jbigkit-libs libXcomposite libXcursor libXdamage libXfixes libXft libXi libXinerama libXmu libXp libXrandr libXrender libXt libXtst libXxf86vm libblkid libcap libcurl-devel libdatrie libdrm libepoxy libgcc libgcrypt libgpg-error libmount libthai libtiff libuuid-devel libwayland-client libwayland-cursor libwayland-egl libwayland-server lz4-libs mesa-libgbm motif nspr nss nss-util pango pixman systemd-libs xz-libs aspell elfutils-libelf enchant2 gstreamer1 gstreamer1-plugins-base harfbuzz-icu hyphen libatomic libglvnd libglvnd-egl libglvnd-gles libglvnd-glx libglvnd-opengl libibverbs libicu libicu50 libnl3 libnotify libpciaccess libpng12 librdmacm libsecret libsoup libstdc++ libtirpc libwebp libwpe libxml2 libxshmfence libxslt libzstd ncurses-libs nss-softokn numactl-libs openjpeg2 orc perl-devel ucx webkit2gtk3 webkit2gtk3-jsc woff2 wpebackend-fdo compat-openssl10 glibc.i686 nss-softokn-freebl audit-libs compat-hwloc1 flac-libs gsm libXdmcp libasyncns libcap-ng libfontenc libogg libsndfile libvorbis ncurses-compat-libs ocl-icd-devel pam pulseaudio-libs pulseaudio-libs-glib2 gtk2 make libICE.i686 libSM.i686 libX11.i686 libXau.i686 libXt.i686 libgcc.i686 libstdc++.i686 libuuid.i686 libxcb.i686 compat-libgfortran-48 libquadmath libtheora freeglut libtool-ltdl mesa-libGLU tbb libtirpc-devel xterm libreoffice-ure ocl-icd octave pciutils-libs libgomp libXScrnSaver"

# Install Development Tools
DEV_TOOLS="@Development Tools"

echo "Installing required packages..."
dnf install -y $PKG_INSTALL $ANSYS_PKGS $DEV_TOOLS

# Remove podman if installed
echo "Checking for podman..."
if rpm -q podman &>/dev/null; then
    echo "Removing podman..."
    dnf remove -y podman
else
    echo "Podman not installed."
fi

# Configure system settings
echo "Configuring system settings..."

# 1. Disable DNF automatic updates
systemctl disable --now dnf-automatic.timer &>/dev/null || true
systemctl disable --now dnf-automatic.service &>/dev/null || true

# 2. Disable firewalld
systemctl disable --now firewalld &>/dev/null || true

# 3. Disable SELinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
setenforce 0 || true

# 4. Enable SSH X11 forwarding
sed -i 's/^#X11Forwarding no/X11Forwarding yes/' /etc/ssh/sshd_config
if ! grep -q "^X11Forwarding yes" /etc/ssh/sshd_config; then
    echo "X11Forwarding yes" >> /etc/ssh/sshd_config
fi

# 5. Denylist Nouveau kmod
if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf 2>/dev/null; then
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
fi

# 6. Set ptrace scope to unrestricted
if [ -f "/etc/sysctl.d/10-ptrace.conf" ]; then
    sed -i 's/^kernel.yama.ptrace_scope.*/kernel.yama.ptrace_scope = 0/' /etc/sysctl.d/10-ptrace.conf
else
    echo "kernel.yama.ptrace_scope = 0" > /etc/sysctl.d/10-ptrace.conf
fi
sysctl -w kernel.yama.ptrace_scope=0

# 7. Set RLIMITS to unlimited
cat > /etc/security/limits.d/99-hpc-limits.conf << 'EOF'
*               soft    cpu             unlimited
*               hard    cpu             unlimited
*               soft    memlock         unlimited
*               hard    memlock         unlimited
*               soft    stack           unlimited
*               hard    stack           unlimited
EOF

# 8. Configure systemd RLIMITs
mkdir -p /etc/systemd/system.conf.d/
cat > /etc/systemd/system.conf.d/99-hpc-limits.conf << 'EOF'
[Manager]
DefaultLimitCPU=infinity
DefaultLimitMEMLOCK=infinity
DefaultLimitSTACK=infinity
EOF

# 9. Enable user namespaces
if [ -f "/etc/sysctl.d/userns.conf" ]; then
    sed -i 's/^user.max_user_namespaces.*/user.max_user_namespaces = 15000/' /etc/sysctl.d/userns.conf
else
    echo "user.max_user_namespaces = 15000" > /etc/sysctl.d/userns.conf
fi
sysctl -w user.max_user_namespaces=15000

# Reload systemd configuration
systemctl daemon-reload

echo "=== Ansys HPC Image Customization Complete ==="
echo "$(date)"