#!/bin/bash
#
# Edera Installer - Remote Installation Script
#
# This script copies the installation files to a remote node and runs the installer.
#
# Usage: INSTALLER_IP=<node-ip> ./scripts/install.sh
#
# Environment variables:
#   INSTALLER_IP  - Required. IP address of the target node
#   SSH_USER      - SSH username (default: root)
#   SSH_KEY       - Path to SSH private key (optional)
#

set -e

# Check that INSTALLER_IP is set
if [ -z "$INSTALLER_IP" ]; then
    echo "Error: INSTALLER_IP is not set"
    echo "Usage: INSTALLER_IP=<node-ip> ./scripts/install.sh"
    echo ""
    echo "Environment variables:"
    echo "  SSH_USER  - SSH username (default: root)"
    echo "  SSH_KEY   - Path to SSH private key (optional)"
    exit 1
fi

# Check that key.json exists
if [ ! -f "key.json" ]; then
    echo "Error: key.json not found"
    echo "Please save your Google Artifact Registry key as key.json"
    exit 1
fi

# Set defaults
SSH_USER=${SSH_USER:-root}
SSH_OPTS=""
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="-i $SSH_KEY"
fi

echo "Installing Edera on $INSTALLER_IP (user: $SSH_USER)..."

# Copy files to target node
scp $SSH_OPTS ./key.json ${SSH_USER}@${INSTALLER_IP}:/tmp/
scp $SSH_OPTS ./scripts/edera-install.sh ${SSH_USER}@${INSTALLER_IP}:~

# Run the installer (use sudo if not root)
if [ "$SSH_USER" = "root" ]; then
    ssh $SSH_OPTS "${SSH_USER}@${INSTALLER_IP}" 'chmod +x ~/edera-install.sh && ~/edera-install.sh'
else
    ssh $SSH_OPTS "${SSH_USER}@${INSTALLER_IP}" 'chmod +x ~/edera-install.sh && sudo ~/edera-install.sh'
fi

echo ""
echo "Installation complete on $INSTALLER_IP"
