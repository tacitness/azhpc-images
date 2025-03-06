#!/bin/bash
set -ex

# jq is needed to parse the component versions from the requirements.json file
yum install -y jq wget tmux vim 
if ! yum localinstall -y files/*.rpm; then echo "Kernel Excluded;"; cat /etc/{yum.conf,dnf/dnf.conf}; rpm -qa | grep -i ^kernel; echo "exclude=kernel*" | tee -a /etc/dnf/dnf.conf -a /etc/yum.conf; fi
