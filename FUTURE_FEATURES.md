# Future Features & Plánovaná vylepšení (testudines-system)

Tento dokument slouží k evidenci plánovaných architektonických rozšíření a vylepšení infrastruktury a nasazení systému Testudines.

---

## 1. Bezpečné verzování produkčních hesel a tokenů v Gitu (Ansible Vault)

### Současný stav:
Produkční tajemství (hesla k VM a databázi, Tailscale autorizační klíč, Cloudflare Tunnel token) jsou uložena v lokálním souboru `deploy/vars.yml`. Tento soubor je vyloučen z verzování přes `.gitignore`, aby nedošlo k úniku citlivých údajů do vzdáleného Git repozitáře. 
Nevýhodou je nutnost ručního přenášení souboru `deploy/vars.yml` na nový server při zotavení po havárii (disaster recovery).

### Návrh řešení (Ansible Vault):
Zabezpečení tajemství šifrováním přímo v Git repozitáři pomocí nástroje `ansible-vault`. Šifrovaný soubor může být bezpečně commitnut do veřejného i soukromého repozitáře.

#### Postup implementace:
1. **Zašifrování citlivých proměnných:**
   Vytvoří se soubor `ansible/vault.yml` obsahující produkční tajemství:
   ```yaml
   vm_password: "..."
   tailscale_auth_key: "..."
   cloudflare_tunnel_token: "..."
   nextcloud_mysql_root_password: "..."
   nextcloud_mysql_password: "..."
   jdownloader_password: "..."
   ```
   Tento soubor se zašifruje silným hlavním heslem (master password):
   ```bash
   ansible-vault encrypt ansible/vault.yml
   ```

2. **Integrace do Ansible playbooku (`site.yml`):**
   V `site.yml` se přidá načítání zašifrovaného souboru:
   ```yaml
   vars_files:
     - vars.yml
     - vault.yml
   ```
   Hodnoty z `vault.yml` mají přednost před výchozími šablonami v `vars.yml`.

3. **Spouštění v `bootstrap.sh`:**
   Pro automatizované spuštění bez interaktivního zadávání hesla lze:
   - Předat cestu k heslu přes soubor:
     ```bash
     ansible-playbook -i inventory.yml site.yml -c local --vault-password-file /root/.vault_pass
     ```
   - Nebo se dotázat na heslo při spuštění bootstrap skriptu:
     ```bash
     ansible-playbook -i inventory.yml site.yml -c local --ask-vault-pass
     ```

---

## 2. Automatizovaný monitoring stavu kontejnerů a diskového prostoru

- Doplnění lehkého exportéru metrik (např. Prometheus node-exporter a cAdvisor nebo Glances) pro sledování využití diskových oddílů (`/mnt/data-sync`, `/mnt/data-nosync`).
- Nastavení notifikací (např. přes Telegram / Discord webhook) v případě selhání kontejneru nebo docházejícího místa.

---

## 3. Systémové a aplikační Push notifikace (Proxmox VE + Nextcloud + Backrest)

### Kontext & Současný stav:
- Proxmox VE (detekce chyb disků přes SMART a degradace ZFS poolu) a Backrest (chyby záloh a vypršení Rclone tokenů) vyžadují spolehlivé odesílání alertů správci.
- Výchozí e-mailový mechanismus v Proxmoxu (`sendmail` / přímý Postfix bez relay) selhává, protože poskytovatelé internetu typicky blokují odchozí port 25 a cílové servery (Gmail, Seznam) zahazují zprávy bez SPF/DKIM z nedůvěryhodných IP adres.
- Uživatel má na mobilu trvale nainstalovanou a připojenou aplikaci **Nextcloud** a nechce instalovat další messengery ani nastavovat placené SMTP služby.
- Nextcloud uvnitř virtuálního stroje (VM) naslouchá z bezpečnostních důvodů striktně na `127.0.0.1:80` a ven je vystaven výhradně přes **Tailscale Serve** (`https://<tailscale-domain>`). Veřejná doména (např. DuckDNS) není v provozu.
- Správce k Proxmoxu přistupuje na LAN IP `https://10.0.1.26:8006` přes **Tailscale Subnet Router**, který inzeruje podsíť `10.0.1.0/24`.

---

### Návrh řešení a postup zprovoznění:

#### 1. Příprava v Nextcloudu (Admin Notifications App)
Oficiální aplikace Nextcloud v telefonu umí nativně přijímat systémové push notifikace bez stahování dalších aplikací:
1. V Nextcloud App Store povolit oficiální bezplatnou aplikaci **Admin Notifications**.
2. V profilu správce (**Osobní nastavení -> Zabezpečení -> Zařízení a relace**) vygenerovat dedikované **Heslo k aplikaci** (např. `Proxmox-Alerts`).
3. Notifikace se odesílají HTTP POST požadavkem na OCS API:
   ```bash
   POST https://<nextcloud-url>/ocs/v2.php/apps/admin_notifications/api/v1/notifications/<uzivatel>
   Hlavičky:
     OCS-APIRequest: true
     Content-Type: application/x-www-form-urlencoded
   Data:
     shortMessage=Titulek zprávy
     longMessage=Podrobný popis chyby
   ```
   *Nextcloud server následně přes svůj odchozí internet kontaktuje oficiální bránu `push-notifications.nextcloud.com`, která doručí systémový push na telefon.*

#### 2. Řešení síťové konektivity z Proxmoxu do Nextcloudu
Protože Nextcloud naslouchá na `127.0.0.1:80` uvnitř VM a je dostupný jen přes Tailscale:

- **Varianta A: Zapojení Proxmox hostitele do Tailnetu (Doporučeno)**
  - Na Proxmox hostiteli nainstalovat Tailscale:
    ```bash
    curl -fsSL https://tailscale.com/install.sh | sh
    tailscale up --authkey=<reusable_authkey_z_deploy_vars>
    ```
  - Proxmox získá přímý přístup k MagicDNS a vidí přímo na `https://<tailscale-domain>`.
  - V Proxmox GUI (**Datacenter -> Notifications -> Targets -> Webhook**) lze přímo nastavit cíl s touto Tailscale URL.
  - *Bonus:* Zabezpečený přístup do Proxmox GUI (`:8006`) odkudkoliv přes Tailscale.

- **Varianta B: Hypervizorové volání přes QEMU Guest Agent (`qm guest exec`)**
  - Pokud na Proxmox nechceme instalovat Tailscale ani měnit vazbu portu `127.0.0.1`:
  - Proxmox využije běžící `qemu-guest-agent` ve VM a spustí skript uvnitř virtuálky:
    ```bash
    qm guest exec 200 -- /usr/local/bin/notify-nextcloud.sh "$TITLE" "$MESSAGE"
    ```
  - Příkaz proběhne přímo v kontextu VM, kde Nextcloud na `127.0.0.1:80` bez problémů odpoví. Nevyžaduje žádné síťové změny.

- **Varianta C: Dedikovaný externí notifikační kanál pro Proxmox (Telegram Bot / ntfy.sh)**
  - Pro případ totálního selhání virtuálního stroje nebo disku, kde VM leží (kdy Nextcloud neběží). Proxmox odešle alert přímo přes internet na Telegram nebo ntfy.sh.

#### 3. Integrace na straně Backrestu
- V plánu záloh (Plan -> Hooks -> On Error) nastavit volání skriptu `/scripts/notify-nextcloud.sh`.
- Skript v kontejneru komunikuje přímo s Tailscale HTTPS doménou Nextcloudu (`https://<tailscale-domain>`), která je z VM a Dockeru nativně dostupná.

