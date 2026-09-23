#!/usr/bin/env bash
set -e

echo "Starting Proxmox Home Server Bootstrap (VM Architecture)..."

# Configure Proxmox VE repository (switch from enterprise to no-subscription if necessary)
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    echo "Disabling pve-enterprise repository..."
    mv /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak 2>/dev/null || true
fi

PVE_CODENAME="bookworm"
if [ -f /etc/os-release ]; then
    DETECTED_CODENAME=$(grep -E '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    [ -n "$DETECTED_CODENAME" ] && PVE_CODENAME="$DETECTED_CODENAME"
fi

NO_SUB_LIST="/etc/apt/sources.list.d/pve-no-subscription.list"
if [ ! -f "$NO_SUB_LIST" ] && [ ! -f /etc/apt/sources.list.d/pve-install-repo.list ]; then
    echo "Configuring Proxmox VE no-subscription repository for $PVE_CODENAME..."
    echo "deb http://download.proxmox.com/debian/pve $PVE_CODENAME pve-no-subscription" > "$NO_SUB_LIST"
fi

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
