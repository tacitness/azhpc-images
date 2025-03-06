#!/bin/bash
set -ex

# Set default repo to Vault 8.9
#cp ./files/*.repo /etc/yum.repos.d/
dnf clean all


# Update 
dnf install -y tmux vim wget
