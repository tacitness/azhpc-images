#!/bin/bash
set -ex

# Update 
dnf clean all
dnf install -y tmux vim wget jq 

dnf --disableexcludes=all install kernel-rpm-macros kernel-{debug-devel,devel,headers,modules-extra}-$(uname -r)
# Uncomment on first build:
# reboot
