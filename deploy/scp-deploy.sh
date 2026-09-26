#!/usr/bin/env bash
set -e

# Skript pro zkopírování vars.yml, bootstrap.sh a ansible složky na Proxmox VE server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/vars.yml"
BOOTSTRAP_FILE="$SCRIPT_DIR/bootstrap.sh"
ANSIBLE_DIR="$(dirname "$SCRIPT_DIR")/ansible"

PROXMOX_HOST="$1"

if [ ! -f "$VARS_FILE" ]; then
    echo "CHYBA: Soubor vars.yml nebyl nalezen v $SCRIPT_DIR!"
    exit 1
fi

if [ -z "$PROXMOX_HOST" ]; then
    read -rp "Zadejte IP adresu nebo hostname Proxmox serveru: " PROXMOX_HOST
fi

if [ -z "$PROXMOX_HOST" ]; then
    echo "CHYBA: Nebyla zadána žádná IP adresa."
    exit 1
fi

REMOTE_DEPLOY_DIR="/opt/testudines-system/deploy"
REMOTE_ANSIBLE_DIR="/opt/testudines-system/ansible"

echo ""
echo "==> 1. Vytvářím adresáře na $PROXMOX_HOST..."
ssh -o StrictHostKeyChecking=accept-new "root@$PROXMOX_HOST" "mkdir -p $REMOTE_DEPLOY_DIR $REMOTE_ANSIBLE_DIR"

echo "==> 2. Kopíruji vars.yml..."
scp "$VARS_FILE" "root@$PROXMOX_HOST:$REMOTE_DEPLOY_DIR/vars.yml"

if [ -f "$BOOTSTRAP_FILE" ]; then
    echo "==> 3. Kopíruji bootstrap.sh..."
    scp "$BOOTSTRAP_FILE" "root@$PROXMOX_HOST:$REMOTE_DEPLOY_DIR/bootstrap.sh"
    ssh "root@$PROXMOX_HOST" "chmod +x $REMOTE_DEPLOY_DIR/bootstrap.sh"
fi

if [ -d "$ANSIBLE_DIR" ]; then
    echo "==> 4. Kopíruji aktuální Ansible soubory..."
    scp -r "$ANSIBLE_DIR"/* "root@$PROXMOX_HOST:$REMOTE_ANSIBLE_DIR/"
fi

echo ""
echo "=== HOTOVO: Soubory byly úspěšně nahrány na $PROXMOX_HOST ==="
echo "Pro spuštění bootstrapu spusťte:"
echo "  ssh root@$PROXMOX_HOST"
echo "  cd $REMOTE_DEPLOY_DIR"
echo "  bash bootstrap.sh"
echo ""
