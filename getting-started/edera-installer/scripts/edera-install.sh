#!/bin/bash
#
# Edera Installer - Node Installation Script
#
# This script runs on the target node to install Edera.
# It automatically detects docker or nerdctl and uses whichever is available.
#

set -e

# Detect container client (docker or nerdctl)
CLIENT=""
for cmd in docker nerdctl; do
    if which $cmd &>/dev/null; then
        CLIENT=$(which $cmd)
        break
    fi
done

if [ -z "$CLIENT" ]; then
    echo "Error: No container client found (docker or nerdctl required)"
    exit 1
fi

echo "Using container client: $CLIENT"

# Edera version to install
TAG="v1.5.1"

echo "Installing Edera $TAG..."

# Login to Google Artifact Registry
$CLIENT login us-central1-docker.pkg.dev -u _json_key --password-stdin </tmp/key.json

# Pull the installer image
$CLIENT pull us-central1-docker.pkg.dev/edera-protect/staging/protect-installer:${TAG}

# Run the installer
$CLIENT run \
    --privileged \
    --env 'TARGET_DIR=/host' \
    --volume '/:/host' \
    --volume "$HOME/.docker/config.json:/root/.docker/config.json" \
    --pid host \
    --net host \
    us-central1-docker.pkg.dev/edera-protect/staging/protect-installer:${TAG}

echo ""
echo "Edera $TAG installed successfully!"
