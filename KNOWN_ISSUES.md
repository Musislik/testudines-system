# Known Issues & Limity architektury (testudines-system)

Tento dokument eviduje známé limity, specifika chování a doporučené postupy pro infrastrukturu a správu virtuálního stroje Testudines.

---

## 1. Asynchronní detekce SCSI zařízení (`/dev/sdb` vs `/dev/sdc`)

### Popis chování:
Virtuální stroj má v KVM/Proxmoxu nakonfigurována tři virtuální SCSI zařízení:
* `scsi0` (40 GB): Kořenový disk operačního systému (v Debianu standardně `/dev/sda`).
* `scsi1` (100 GB): Persistentní datový disk (`/mnt/data-sync`), který je **zahrnut do zálohování** Proxmox Backup Serveru (PBS) i Google Drive mirroringu.
* `scsi2` (250 GB): Nestálý datový disk (`/mnt/data-nosync`) pro dočasná stahování (JDownloader), který má v Proxmoxu explicitně nastaven příznak `backup=0` (**vyřazen ze zálohování**).

Linuxové jádro při bootu přiřazuje písmena blokových zařízení (`/dev/sda`, `/dev/sdb`, `/dev/sdc`...) sekvenčně podle toho, jak jednotlivá zařízení odpoví během inicializace sběrnice SCSI. 

### Riziko (Failure Mode):
Za standardních okolností se `scsi1` stane `/dev/sdb` a `scsi2` se stane `/dev/sdc`.
Pokud však dojde k:
1. Přidání dalšího virtuálního disku (např. passthrough fyzického disku nebo dočasného disku `scsi3`),
2. Připojení USB zařízení do KVM,
3. Změně pořadí inicializace ovladačů jádra po aktualizaci linuxového jádra,
může dojít k **prohození písmen zařízení** (`scsi1` dostane `/dev/sdc` a `scsi2` dostane `/dev/sdb`).

**Důsledky statického mountu podle `/dev/sdX`:**
- Pokud by v `/etc/fstab` zůstaly statické cesty `/dev/sdb` a `/dev/sdc`, po restartu by se na `/mnt/data-sync` připojil disk s `backup=0` (250 GB) a na `/mnt/data-nosync` disk se zálohováním (100 GB).
- Došlo by k okamžitému selhání zálohování (zálohovala by se dočasná stahování namísto databází Nextcloudu a herních světů), případně k chybám zápisu z důvodu odlišných kapacit.

### Jak zkontrolovat aktuální stav:
Na virtuálním stroji spusťte:
```bash
lsblk -o NAME,SIZE,MOUNTPOINT,LABEL,UUID
```
nebo:
```bash
findmnt /mnt/data-sync
findmnt /mnt/data-nosync
```
Zkontrolujte, zda 100GB oddíl odpovídá `/mnt/data-sync` a 250GB oddíl odpovídá `/mnt/data-nosync`.

### Trvalé a bezpečné řešení (Filesystem Labels):
Namísto nestabilních jmen zařízení `/dev/sdb` a `/dev/sdc` se doporučuje používat jmenovky souborového systému (Labels) nebo UUID:

1. **Nastavení jmenovek oddílů (pokud chybí):**
   ```bash
   # Zjistěte, který disk je skutečně 100GB (data-sync) a který 250GB (data-nosync)
   e2label /dev/sdb data-sync
   e2label /dev/sdc data-nosync
   ```

2. **Úprava `/etc/fstab`:**
   Nahraďte statické cesty zápisem pomocí `LABEL=`:
   ```fstab
   LABEL=data-sync    /mnt/data-sync    ext4    defaults,discard    0 2
   LABEL=data-nosync  /mnt/data-nosync  ext4    defaults,discard    0 2
   ```
   *Poznámka:* Volba `discard` v fstab umožňuje jádru předávat TRIM požadavky dolů na Proxmox ZFS/LVM úložiště. Toto bezpečné formátování s jmenovkami a mount pomocí `LABEL=` je již plně automatizováno v Ansible playbooku `site.yml`.

---

## 2. Proxmox VE Enterprise repozitář na čisté instalaci

### Popis problému:
Při instalaci čistého Proxmox VE je ve výchozím stavu aktivní repozitář `pve-enterprise`. Ten bez zakoupeného předplatného vrací při spuštění `apt-get update` kód HTTP 401 Unauthorized. 
Protože skript `bootstrap.sh` používá striktní ukončení při chybě (`set -e`), první běh `apt-get update` na čistém hostiteli může selhat.

### Řešení před spuštěním `bootstrap.sh`:
Na hostiteli Proxmox zakažte enterprise repozitář a povolte no-subscription repozitář:
```bash
# Deaktivace enterprise repozitáře
rm -f /etc/apt/sources.list.d/pve-enterprise.list

# Přidání no-subscription repozitáře (pro Proxmox VE 8.x Bookworm)
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list

# Aktualizace indexů
apt-get update
```

---

## 3. Paměťové limity a absence SWAPu v Debian Generic Cloud Image

### Popis chování:
Oficiální obraz `debian-12-genericcloud-amd64.qcow2` ve výchozím stavu nevytváří žádný odkládací prostor (SWAP). Virtuální stroj má alokováno 16 GB RAM (`vm_memory: 16384`), přičemž samotný Minecraft server má alokováno až 10 GB (`minecraft_memory: "10240M"`).

### Riziko:
Pokud se sečte paměťová špička Minecraftu s provozem Nextcloudu (PHP worker procesy, Apache, MariaDB buffer pool, Redis cache) a JDownloaderu (Java JVM), může dojít k vyčerpání fyzické RAM. V takovém případě Linuxový OOM Killer (Out-of-Memory Killer) okamžitě ukončí nejnáročnější proces (zpravidla MariaDB nebo Java).

### Doporučené řešení:
Na kořenovém disku VM (`scsi0`, 40 GB) vytvořit odkládací soubor o velikosti 4 až 8 GB:
```bash
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab
```
