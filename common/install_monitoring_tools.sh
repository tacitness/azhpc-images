#!/bin/bash

set -ex

source ${COMMON_DIR}/utilities.sh

# Set the Moneo version
moneo_metadata=$(get_component_config "moneo")
MONEO_VERSION=$(jq -r '.version' <<< $moneo_metadata)

# Dependencies 
python3 -m pip install --upgrade pip

MONITOR_DIR=/opt/azurehpc/tools

mkdir -p $MONITOR_DIR

pushd $MONITOR_DIR

    # Check if Moneo directory already exists
    if [ -d "Moneo" ]; then
        echo "Moneo directory already exists, updating instead of cloning"
        pushd Moneo
            # Fetch the latest changes without modifying local changes
            git fetch origin
            # Check if we're on the expected branch
            CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
            EXPECTED_BRANCH="v$MONEO_VERSION"
            if [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then
                echo "Switching to branch $EXPECTED_BRANCH"
                git checkout $EXPECTED_BRANCH || git checkout -b $EXPECTED_BRANCH origin/$EXPECTED_BRANCH
            fi
        popd
    else
        echo "Cloning Moneo repository"
        git clone https://github.com/Azure/Moneo --branch v$MONEO_VERSION
    fi

    chmod 777 Moneo

    # Check if service is already configured
    if [ -f "/etc/systemd/system/moneo.service" ]; then
        echo "Moneo service already configured, skipping configuration"
    else
        echo "Configuring Moneo service"
        pushd Moneo/linux_service
            ./configure_service.sh
        popd
    fi
popd

# add an alias for Moneo
if ! grep -qxF "alias moneo='python3 /opt/azurehpc/tools/Moneo/moneo.py'" /etc/bash.bashrc; then
    echo "alias moneo='python3 /opt/azurehpc/tools/Moneo/moneo.py'" >> /etc/bash.bashrc
fi

$COMMON_DIR/write_component_version.sh "MONEO" ${MONEO_VERSION}
