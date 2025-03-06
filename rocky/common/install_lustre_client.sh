#!/bin/bash
set -ex

# Set Lustre version
LUSTRE_VERSION=$(jq -r '.lustre."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)

# Expected params:
# $1 = the major version of the distro. "8" for RHEL/Alma8, "9" for RHEL/Alma9.

#source $ROCKY_COMMON_DIR/setup_lustre_repo.sh "$1"

curl https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -o /tmp/fsx-rpm-public-key.asc
rpm --import /tmp/fsx-rpm-public-key.asc
curl https://fsx-lustre-client-repo.s3.amazonaws.com/el/8/fsx-lustre-client.repo -o /etc/yum.repos.d/aws-fsx.repo

# If using rpm path uncomment
dnf install -y --disableexcludes=main --refresh kmod-lustre-client lustre-client
sed -i "$ s/$/ amlfs*/" /etc/dnf/dnf.conf
sed -i "$ s/$/ kmod*/" /etc/dnf/dnf.conf

$COMMON_DIR/write_component_version.sh "LUSTRE" ${LUSTRE_VERSION}
