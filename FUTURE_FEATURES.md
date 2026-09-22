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
