# Testudines Deployment Guide (`deploy/`)

Tato příručka popisuje postup nasazení a obnovy systému Testudines na hostiteli Proxmox VE pomocí skriptu `bootstrap.sh`.

---

## 1. Příprava před nasazením

Před spuštěním nasazení je nutné mít připraven privátní konfigurační soubor `deploy/vars.yml` (který je vyloučen z verzování v Gitu pomocí `.gitignore`).

### Důležité: Generování Tailscale Auth Key (Reusable)
Při generování autentizačního klíče v administraci Tailscale je **nezbytné vytvořit klíč pro opakované použití**:
1. Otevřete [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2. Přejděte do **Settings** -> **Keys** -> **Generate auth key**.
3. **Zaškrtněte volbu "Reusable" (Opakovaně použitelný)**.
   > [!IMPORTANT]
   > Pokud použijete výchozí jednorázový klíč (single-use), první instalace proběhne v pořádku, ale jakékoliv budoucí spuštění playbooku, aktualizace VM nebo přeinstalace selže s chybou `authkey already used`.
4. Vygenerovaný klíč vložte do `deploy/vars.yml`:
   ```yaml
   tailscale_auth_key: "tskey-auth-..."
   ```

### Nastavení `tailscale_domain` pro zabezpečený HTTPS přístup
Systém používá automatickou detekci přidělené Tailscale IP adresy pro striktní vazbu administrativních rozhraní (Dockge, JDownloader, Firefox) pouze na `127.0.0.1` a vaši reálnou Tailscale IP adresu:
1. Zjistěte vaši Tailscale doménu v [Tailscale Admin Console](https://login.tailscale.com/admin/dns) (např. `testudines.tailxxxx.ts.net`).
2. Ujistěte se, že v Tailscale administraci máte povoleny HTTPS certifikáty (**DNS** -> **Enable HTTPS Certificates**).
3. Nastavte hodnotu v `deploy/vars.yml`:
   ```yaml
   tailscale_domain: "testudines.tailxxxx.ts.net"
   ```
4. Ansible playbook po připojení do Tailnetu automaticky:
   - Dynamicky zjistí přidělenou Tailscale IP adresu (`tailscale ip -4`) a sváže na ni administrativní porty (5001, 5800, 3000). Ty tak nejsou přístupné z domácí sítě LAN (`10.0.1.x`), ale výhradně z VPN sítě Tailscale nebo přes SSH tunel (`localhost`).
   - Aktivuje **Tailscale Serve**, který automaticky vystaví Nextcloud na HTTPS portu 443 s důvěryhodným certifikátem Let's Encrypt.


---

## 2. Spuštění instalace (Bootstrap)

1. Připojte se na čistý hostitelský systém Proxmox VE přes SSH jako uživatel `root`.
2. Naklonujte repozitář `testudines-system`:
   ```bash
   git clone https://github.com/musislik/testudines-system.git /opt/testudines-system
   ```
3. Zkopírujte váš privátní soubor `vars.yml` do složky `/opt/testudines-system/deploy/`:
   ```bash
   # Příklad přenosu z lokálního počítače:
   scp deploy/vars.yml root@<proxmox-ip>:/opt/testudines-system/deploy/vars.yml
   ```
4. (Doporučeno) Spusťte validační skript pro ověření konfigurace:
   ```bash
   cd /opt/testudines-system
   python3 scripts/validate.py
   ```
5. Spusťte bootstrapovací skript:
   ```bash
   cd /opt/testudines-system/deploy
   bash bootstrap.sh
   ```

### Jak `bootstrap.sh` funguje:
- Nainstaluje potřebné systémové nástroje (`ansible`, `git`, `rsync`, `python3`).
- Zkontroluje přítomnost privátního souboru `deploy/vars.yml`.
- Spustí Ansible playbook s parametrem `-e @deploy/vars.yml`. **Sledovaný soubor `ansible/vars.yml` v Gitu se nepřepisuje**, takže pracovní strom repozitáře zůstává čistý a budoucí příkazy `git pull` nezpůsobí konflikt.
- Vytvoří KVM virtuální stroj (Debian 12 Bookworm) s disky `scsi0` (OS), `scsi1` (data-sync pro zálohování) a `scsi2` (data-nosync bez zálohování).
- Nainstaluje Docker CE, Tailscale, synchronizuje aplikační stacky z `testudines-stacks` a spustí všechny kontejnery.

---

## 3. Přístup k nasazeným službám

Po dokončení instalace jsou služby dostupné následovně:

| Služba | Port | Rozhraní / Přístup | URL / Adresa |
|---|---|---|---|
| **Nextcloud** | 443 (HTTPS) | Pouze Tailscale | `https://<tailscale-domain>` (přes Tailscale Serve s Let's Encrypt certifikátem) |
| **Dockge (Správce stacků)** | 5001 | Pouze Tailscale & Localhost | `http://<tailscale-ip>:5001` (nebo `localhost:5001` přes SSH tunel) |
| **JDownloader 2** | 5800 (HTTPS) | Pouze Tailscale & Localhost | `https://<tailscale-ip>:5800` (self-signed certifikát; nebo přes SSH tunel) |
| **Firefox Web-Client** | 3000 | Pouze Tailscale & Localhost | `http://<tailscale-ip>:3000` (nebo `localhost:3000` přes SSH tunel) |
| **Minecraft Server** | 25565 | Všechna rozhraní | `testudines:25565` |
| **OpenTTD Server** | 3979 | Všechna rozhraní (TCP/UDP) | `testudines:3979` |

