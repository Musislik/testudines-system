# Testudines Server Architecture & Implementation Plan

## 1. Infrastructure & Deployment Strategy
* **Platform:** Proxmox VE (Virtual Environment)
* **Management & Deployment:** Two-Repository Git Strategy + Bootstrap Script (Ansible local deployment mode).
  * **Repository 1 (`testudines-system`):** Infrastructure as Code (Proxmox host configuration, KVM VM provisioning via Cloud-Init, PBS/Rclone backups, and Ansible automation).
  * **Repository 2 (`testudines-apps`):** Docker Compose stacks organized in a flat directory structure under `stacks/<stack-name>/compose.yaml` (directly mapping to `/opt/stacks/` in Dockge).
* **Rationale:** Maximizes hardware utilization and operational stability by running Docker inside a dedicated lightweight KVM Virtual Machine (Debian 12 Bookworm) with native `ext4` formatting and the standard Linux kernel `overlay2` storage driver, completely avoiding the known ZFS/LXC storage driver issues.
* **Shared Configuration & Secrets Management:**
   * `testudines-system/ansible/vars.yml` serves as the Git-safe repository template containing variable definitions with placeholders (`YOUR-...`).
   * `testudines-system/deploy/vars.yml` is the administrator's private deployment file kept strictly locally (excluded from Git via `.gitignore`), containing production credentials and tokens.
   * During bootstrap, `bootstrap.sh` loads the local `deploy/vars.yml` via Ansible extra-vars (`-e @$LOCAL_VARS`), keeping the Git working tree completely clean and avoiding merge conflicts on subsequent updates.
   * **Tailscale Auth Key Requirement:** The `tailscale_auth_key` must be generated as a **Reusable key** in the Tailscale Admin Console (Settings -> Keys -> Generate auth key -> check *Reusable*). This ensures that repeat Ansible runs or VM reprovisioning do not fail due to a consumed single-use key.
   * Ansible injects these values directly into `.env` files within target stacks during provisioning.
* **Disaster Recovery (Bootstrap):** In the event of a total failure, recovery involves installing a clean Proxmox OS, connecting via SSH, and running `bootstrap.sh`. This script installs Ansible, downloads the Debian Cloud Image, creates the VM with Cloud-Init, sets up networking and disks, installs Docker CE and Tailscale, clones application stacks, injects environment variables, and starts all services.

## 2. Storage & RAID Guidelines
*Due to the use of an HPE SAS Controller, special care must be taken regarding ZFS.*

### Rule: DO NOT USE "RAID 0 per disk" for ZFS
Using individual RAID 0 arrays to simulate direct disk access is highly discouraged and dangerous for ZFS (causes S.M.A.R.T. data masking, cache conflicts, loss of pool portability, and interferes with error handling).

### Approved Storage Configurations:
* **Option A: True HBA Mode (Preferred for ZFS)**
  * Requires enabling true HBA mode on the existing controller (e.g., via `ssacli ctrl slot=0 modify hbamode=on`) or using a dedicated PCIe LSI HBA card flashed to "IT mode".
  * **Setup:** Proxmox uses native **ZFS** (RAIDZ1 or RAIDZ2). Unlocks bit-rot protection and instant snapshots.
* **Option B: Native Hardware RAID (Fallback)**
  * If true HBA mode is unavailable, create a standard hardware RAID array (e.g., RAID 5 or 6) directly in the HPE controller BIOS.
  * **Setup:** Proxmox uses standard **LVM/ext4** or **XFS**. Highly stable, utilizing the hardware as intended.

### Storage Layout for the Docker VM:
* **Root OS Disk (`scsi0`, 40 GB):** Formatted with `ext4`. Docker uses the native kernel `overlay2` driver.
* **Data-Sync Disk (`scsi1`, 100 GB):** Formatted with `ext4`, mounted at `/mnt/data-sync`. Hosts persistent, backed-up application data (Nextcloud, Minecraft world, OpenTTD saves).
* **Data-NoSync Disk (`scsi2`, 250 GB):** Formatted with `ext4`, mounted at `/mnt/data-nosync`. Marked with `backup=0` in Proxmox to exclude temporary downloads (e.g., JDownloader `/output`) from PBS backups, saving storage and cloud bandwidth.

## 3. Backup Strategy & Google Drive Integration
* **Mechanism:** Proxmox Backup Server (PBS) + Rclone mirroring to 5TB Google Drive.
* **Workflow:**
  1. A local PBS instance creates highly compressed and deduplicated block-level backups of the Docker VM.
  2. Rclone securely encrypts and syncs these backup blocks to remote Google Drive storage.
  3. Recovery consists of downloading the repository from Google Drive and performing a one-click full VM restore.
* **Excluded Storage:** The temporary downloads virtual disk (`scsi2`) has the "Include in backup" flag unchecked (`backup=0`).

## 4. Containerization & Networking
* **Network Topology (Unified Docker VM):**
  * **VM IP:** `10.0.1.226/24` on bridge `vmbr0`.
  * **Tailscale Mesh VPN:** Installed directly on the VM operating system. Provides zero-trust, authenticated, encrypted remote access to Nextcloud (Tailscale Serve HTTPS on port `443` at `https://<tailscale-domain>`), administration tools (Dockge on port `5001`, JDownloader on port `5800`), and private services without opening any router ports.
  * **Strict Administrative Network Isolation:** Sensitive administration interfaces (Dockge on port `5001`, JDownloader on port `5800`, Firefox Web-client on port `3000`) are explicitly bound only to `127.0.0.1` and `TAILSCALE_IP`. They are not exposed to the local LAN (`10.0.1.x`), ensuring access is restricted to localhost (via SSH tunnels) and authenticated Tailscale mesh peers.
  * **Cloudflare Tunnel (`cloudflared`):** Runs containerized in Docker, connected to the shared `proxy-tier` Docker bridge network, reserved for external web routing needs without opening firewall/router ports.
  * **Gaming Servers:** Minecraft (port `25565`) and OpenTTD (port `3979`) run containerized and can be reached over Tailscale or via router port-forwarding for external players.
  * **Archived Stacks:** Legacy/redundant stacks (`hamachi`, `docker-tailscale`, `nginx-ingress`, `media-server`, `mopidy`, etc.) are retired to `/disabled` outside of Git.
* **Docker & Compose Management:**
  * Active compose stacks are maintained in `testudines-apps/stacks/` and synchronized to `/opt/stacks` via `rsync -av --delete --exclude='.env'`.
  * Shared Docker bridge network `proxy-tier` connects services.
  * **Dockge** runs managing all stacks under `/opt/stacks`.
