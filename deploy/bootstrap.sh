#!/usr/bin/env bash
set -e

echo "Starting Proxmox Home Server Bootstrap (VM Architecture)..."

# Configure Proxmox VE repository (switch from enterprise to no-subscription if necessary)
echo "Disabling enterprise repositories (PVE and Ceph)..."
for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if [ -f "$f" ] && grep -q "enterprise.proxmox.com" "$f"; then
        echo " - Disabling $f..."
        mv -f "$f" "$f.bak" 2>/dev/null || true
    fi
done
if [ -f /etc/apt/sources.list ] && grep -q "enterprise.proxmox.com" /etc/apt/sources.list; then
    sed -i 's|^\([^#].*enterprise\.proxmox\.com\)|#\1|' /etc/apt/sources.list 2>/dev/null || true
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
REPO_BRANCH="${DEPLOY_BRANCH:-deploy-testing}"
CLONE_DIR="/opt/testudines-system"

if [ -d "$CLONE_DIR/.git" ]; then
    echo "Directory $CLONE_DIR already exists as a git repository. Syncing branch $REPO_BRANCH..."
    cd "$CLONE_DIR"
    git fetch origin
    git checkout -B "$REPO_BRANCH" "origin/$REPO_BRANCH" 2>/dev/null || git checkout "$REPO_BRANCH" 2>/dev/null || true
    git pull origin "$REPO_BRANCH" 2>/dev/null || git pull
elif [ -d "$CLONE_DIR" ]; then
    echo "Directory $CLONE_DIR exists without git metadata. Fetching full repository ($REPO_BRANCH)..."
    TMP_CLONE="/tmp/testudines-clone-$$"
    rm -rf "$TMP_CLONE"
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$TMP_CLONE" 2>/dev/null || git clone "$REPO_URL" "$TMP_CLONE"
    cp -r -n "$TMP_CLONE"/* "$CLONE_DIR"/ 2>/dev/null || true
    cp -r "$TMP_CLONE"/.git "$CLONE_DIR"/
    rm -rf "$TMP_CLONE"
else
    echo "Cloning repository $REPO_URL ($REPO_BRANCH)..."
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR" 2>/dev/null || git clone "$REPO_URL" "$CLONE_DIR"
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
