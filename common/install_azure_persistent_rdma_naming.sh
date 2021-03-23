#!/bin/bash
set -ex

#
# install rdma_rename with NAME_FIXED option
#

pushd /tmp
rdma_core_branch=stable-v34
git clone -b $rdma_core_branch https://github.com/linux-rdma/rdma-core.git
pushd rdma-core
bash build.sh
cp build/bin/rdma_rename /usr/sbin/rdma_rename_$rdma_core_branch
popd
rm -rf rdma-core
popd

#
# setup systemd service
#

cat <<EOF >/usr/sbin/azure_persistent_rdma_naming.sh
#!/bin/bash

rdma_rename=/usr/lib/udev/rdma_rename_${rdma_core_branch}

an_index=0
ib_index=0

for old_device in \$(ibdev2netdev -v | sort -n | cut -f2 -d' '); do

	link_layer=\$(ibv_devinfo -d \$old_device | sed -n 's/^[\ \t]*link_layer:[\ \t]*\([a-zA-Z]*\)\$/\1/p')
	
	if [ "\$link_layer" = "InfiniBand" ]; then
		
		\$rdma_rename \$old_device NAME_FIXED mlx_ib\${ib_index}
		ib_index=\$((\$ib_index + 1))
		
	elif [ "\$link_layer" = "Ethernet" ]; then
	
		\$rdma_rename \$old_device NAME_FIXED mlx_an\${an_index}
		an_index=\$((\$an_index + 1))
		
	else
	
		echo "Unknown device type for \$old_device - \$device_type."
		
	fi
	
done
EOF

cat <<EOF >/etc/systemd/system/azure_persistent_rdma_naming.service
[Unit]
Description=Azure persistent RDMA naming
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/azure_persistent_rdma_naming.sh
RemainAfterExit=true
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable azure_persistent_rdma_naming.service
