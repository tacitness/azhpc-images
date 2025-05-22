#!/bin/bash
############################################################################
# @Brief	: Write the component and its version
#
# @Args		: (1) Component Name
# 			  (2) Version
############################################################################

set -e

# Parameters
component=$1
version=$2

install_dir="/opt/azurehpc"
mkdir -p ${install_dir}
component_versions_json="${install_dir}/component_versions.txt"

# Make sure file exists with valid JSON
if [ ! -f "${component_versions_json}" ]; then
    echo '{}' > ${component_versions_json}
elif ! jq . "${component_versions_json}" > /dev/null 2>&1; then
    echo "WARNING: Invalid JSON in ${component_versions_json}, reinitializing file"
    echo '{}' > ${component_versions_json}
fi

# Add more debug information
echo "Adding component ${component} version ${version} to ${component_versions_json}"
echo "Current content of ${component_versions_json}:"
cat ${component_versions_json}

# Now safely add/update component version
if ! jq ". + {\"${component}\": \"${version}\"}" ${component_versions_json} > ${component_versions_json}.tmp; then
    echo "ERROR: Failed to update component version JSON, manually creating entry"
    echo "{\"${component}\": \"${version}\"}" > ${component_versions_json}.tmp
fi

mv ${component_versions_json}.tmp ${component_versions_json}
echo "Updated content of ${component_versions_json}:"
cat ${component_versions_json}