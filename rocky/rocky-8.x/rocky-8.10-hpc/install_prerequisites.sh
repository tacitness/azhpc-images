#!/bin/bash
set -ex

# jq is needed to parse the component versions from the requirements.json file
yum install -y jq wget tmux vim 
##if ! yum localinstall -y files/*.rpm; then echo "Kernel Excluded;"; cat /etc/{yum.conf,dnf/dnf.conf}; rpm -qa | grep -i ^kernel; echo "exclude=kernel*" | tee -a /etc/dnf/dnf.conf -a /etc/yum.conf; fi

# Uncomment on first build:
#dnf install kernel{,-core,-modules,-tools}-4.18.0-553.5.1.el8_10.x86_64
# reboot
#dnf erase -y kernel{,-core,-modules,-tools}-4.18.0-553.8.1.el8_10.x86_64

dnf --disableexcludes=all install kernel-rpm-macros kernel-{debug-devel,devel,headers,modules-extra}-$(uname -r)
