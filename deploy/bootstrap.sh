#!/usr/bin/env bash
set -e

echo "Starting Proxmox Home Server Bootstrap (VM Architecture)..."

# Update and install required packages on Proxmox VE host
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git curl rsync ansible python3

# Clone the configuration repository
REPO_URL="https://github.com/musislik/testudines-system.git"
CLONE_DIR="/opt/testudines-system"

if [ -d "$CLONE_DIR" ]; then
    echo "Directory $CLONE_DIR already exists. Pulling latest changes..."
    cd $CLONE_DIR && git pull
else
    echo "Cloning repository $REPO_URL..."
    git clone $REPO_URL $CLONE_DIR
fi

# Locate script directory and local vars.yml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_VARS="$SCRIPT_DIR/vars.yml"
EXTRA_VARS_ARG=""

# Check for private deployment variables
if [ -f "$LOCAL_VARS" ]; then
    echo "Using private deployment variables from $LOCAL_VARS..."
    EXTRA_VARS_ARG="-e @$LOCAL_VARS"
else
    echo "Notice: Local $LOCAL_VARS not found, proceeding with repository template vars.yml"
fi

# Run the Ansible playbook locally on the Proxmox host
echo "Running Ansible playbook to provision VM and configure services..."
cd $CLONE_DIR/ansible
ansible-playbook -i inventory.yml site.yml $EXTRA_VARS_ARG


echo "Bootstrap complete! VM and Docker services are up and running."
