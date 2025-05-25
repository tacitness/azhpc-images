#!/bin/bash

# Use set -e but with better error handling throughout the script
set -e

# Set moneo metadata
MONEO_VERSION=$(jq -r '.moneo."'"$DISTRIBUTION"'".version' <<< $COMPONENT_VERSIONS)

# Dependencies 
echo "Installing/upgrading pip..."
python3 -m pip install --upgrade pip

# Adding path to sudo user
echo "Configuring sudo secure path..."
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
            # Check if patch needs to be applied by examining the files
            # The patch modifies nvidia.sh and common.sh, so check their content
            echo "Checking if patch 83 needs to be applied..."
            
            # First check if the source files exist
            if [ ! -f "src/worker/install/nvidia.sh" ] || [ ! -f "src/worker/install/common.sh" ]; then
                echo "Warning: Expected source files not found, skipping patch application"
            elif grep -q "dcgm-exporter --no-file" src/worker/install/nvidia.sh && \
                 grep -q "metrics.d/script/script_exporter.sh" src/worker/install/common.sh; then
                echo "Patch 83 already applied, skipping"
            else
                echo "Applying patch 83..."
                wget -q https://patch-diff.githubusercontent.com/raw/Azure/Moneo/pull/83.patch -O 83.patch
                
                # Apply patch with --forward to ignore already applied hunks
                # and -f (force) to proceed even if the patch doesn't match exactly
                if patch -p1 --forward -f < 83.patch 2>/dev/null; then
                    echo "Patch application was successful"
                else
                    echo "Patch application had some rejections, but this is expected if partially applied"
                    # Clean up any reject files
                    find . -name "*.rej" -exec rm {} \;
                fi
                
                # Verify patch effect is present
                if grep -q "dcgm-exporter --no-file" src/worker/install/nvidia.sh; then
                    echo "✓ Patch effect verified in nvidia.sh"
                else
                    echo "Warning: Patch effect not detected in nvidia.sh"
                fi
                
                # Clean up patch file
                rm -f 83.patch
            fi
        popd
    else
        echo "Cloning Moneo repository"
        git clone https://github.com/Azure/Moneo --branch v$MONEO_VERSION
        pushd Moneo
            echo "Applying patch 83 to fresh clone"
            wget -q https://patch-diff.githubusercontent.com/raw/Azure/Moneo/pull/83.patch -O 83.patch
            
            # Apply patch with --forward to ignore already applied hunks
            # and -f (force) to proceed even if the patch doesn't match exactly
            if patch -p1 --forward -f < 83.patch 2>/dev/null; then
                echo "Patch application was successful"
            else
                echo "Patch application had some rejections, but continuing..."
                # Clean up any reject files
                find . -name "*.rej" -exec rm {} \;
            fi
            
            # Verify patch effect is present
            if grep -q "dcgm-exporter --no-file" src/worker/install/nvidia.sh; then
                echo "✓ Patch effect verified in nvidia.sh"
            else
                echo "Warning: Patch effect not detected in nvidia.sh"
            fi
            
            # Clean up patch file
            rm -f 83.patch
        popd
    fi

    chmod 777 Moneo

    # Check if service is already configured
    if [ -f "/etc/systemd/system/moneo.service" ]; then
        echo "Moneo service already configured, skipping configuration"
    else
        echo "Configuring Moneo service"
        pushd Moneo/linux_service
            # Run configure_service.sh with better error handling
            if ./configure_service.sh; then
                echo "Moneo service configuration completed successfully"
            else
                echo "Warning: Moneo service configuration may have encountered issues, but continuing..."
            fi
        popd
    fi
popd

# add an alias for Moneo
if ! grep -qxF "alias moneo='python3 /opt/azurehpc/tools/Moneo/moneo.py'" /etc/bashrc; then
    echo "Adding Moneo alias to /etc/bashrc"
    echo "alias moneo='python3 /opt/azurehpc/tools/Moneo/moneo.py'" >> /etc/bashrc
else
    echo "Moneo alias already exists in /etc/bashrc"
fi

echo "Recording Moneo version information..."
$COMMON_DIR/write_component_version.sh "MONEO" ${MONEO_VERSION}

echo "==============================================="
echo "Moneo installation completed successfully!"
echo "Version: ${MONEO_VERSION}"
echo "Location: ${MONITOR_DIR}/Moneo"
echo "==============================================="
