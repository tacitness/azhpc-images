#!/bin/bash

set -e

# Set moneo metadata
MONEO_VERSION=$(jq -r '.moneo."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)

# Dependencies 
python3 -m pip install --upgrade pip

# Adding path to sudo user
sed -i 's/.*secure_path.*/Defaults    secure_path = "\/usr\/local\/sbin:\/usr\/local\/bin:\/sbin:\/bin:\/usr\/sbin:\/usr\/bin\/"/' /etc/sudoers

MONITOR_DIR=/opt/azurehpc/tools

if [ ! -d "$MONITOR_DIR" ]; then
    echo "Creating directory: $MONITOR_DIR"
    mkdir -p $MONITOR_DIR
else
    echo "Directory $MONITOR_DIR already exists"
fi

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
            # Apply patch if it hasn't been applied already
            if ! git log --pretty=oneline | grep -q "pull/83"; then
                echo "Applying patch 83"
                wget -q https://patch-diff.githubusercontent.com/raw/Azure/Moneo/pull/83.patch
                patch -p1 < 83.patch
            else
                echo "Patch 83 already applied, skipping"
            fi
        popd
    else
        echo "Cloning Moneo repository"
        git clone https://github.com/Azure/Moneo --branch v$MONEO_VERSION
        pushd Moneo
            wget https://patch-diff.githubusercontent.com/raw/Azure/Moneo/pull/83.patch
            patch -p1 < 83.patch
        popd
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
if ! grep -qxF "alias moneo='python3 /opt/azurehpc/tools/Moneo/moneo.py'" /etc/bashrc; then
    echo "alias moneo='python3 /opt/azurehpc/tools/Moneo/moneo.py'" >> /etc/bashrc
fi

$COMMON_DIR/write_component_version.sh "MONEO" ${MONEO_VERSION}
