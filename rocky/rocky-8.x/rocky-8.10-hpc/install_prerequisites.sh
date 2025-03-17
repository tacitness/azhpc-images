#!/bin/bash
set -ex

# jq is needed to parse the component versions from the requirements.json file
yum install -y jq wget tmux vim 

dnf --disableexcludes=all install kernel-rpm-macros kernel-{debug-devel,devel,headers,modules-extra}-$(uname -r)
# Uncomment on first build:
# reboot
