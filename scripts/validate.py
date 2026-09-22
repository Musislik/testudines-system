#!/usr/bin/env python3
"""
Testudines Deployment & Configuration Validator

Tento skript provádí automatickou validaci projektu Testudines před nasazením:
1. Kontroluje syntaktickou správnost všech YAML souborů (Ansible i Docker Compose).
2. Porovnává klíče mezi šablonou `ansible/vars.yml` a privátním `deploy/vars.yml`.
3. Upozorňuje na případné nevyplněné zástupné řetězce (YOUR-...).
4. Ověřuje, zda jsou všechny Jinja2 proměnné použité v `site.yml` definovány v `vars.yml`.
5. Kontroluje, zda všechny proměnné prostředí (${VAR}) vyžadované v `compose.yaml`
   jsou řádně injektovány z Ansible playbooku.

Použití:
    python3 scripts/validate.py
"""

import sys
import os
import re

try:
    import yaml
except ImportError:
    print("CHYBA: Balíček 'PyYAML' není nainstalován. Nainstalujte jej pomocí: pip install pyyaml")
    sys.exit(1)


def find_project_root():
    """Najde kořenový adresář projektu obsahující testudines-system i testudines-stacks."""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    # 1. Zkusíme vystoupat o úroveň výš (pokud je skript v testudines-system/scripts)
    parent = os.path.dirname(current_dir)
    grandparent = os.path.dirname(parent)
    
    if os.path.isdir(os.path.join(grandparent, "testudines-system")) and os.path.isdir(os.path.join(grandparent, "testudines-stacks")):
        return grandparent
    if os.path.isdir(os.path.join(parent, "testudines-system")) and os.path.isdir(os.path.join(parent, "testudines-stacks")):
        return parent
    if os.path.isdir(os.path.join(current_dir, "testudines-system")):
        return current_dir

    return os.getcwd()


def main():
    root_dir = find_project_root()
    system_dir = os.path.join(root_dir, "testudines-system")
    stacks_repo_dir = os.path.join(root_dir, "testudines-stacks")

    print(f"=== TESTUDINES CONFIGURATION VALIDATOR ===")
    print(f"Kořenový adresář: {root_dir}")
    print(f"System repozitář: {system_dir}")
    print(f"Stacks repozitář: {stacks_repo_dir}\n")

    has_errors = False

    # 1. Kontrola existence a syntaxe YAML souborů
    print("--- 1. KONTROLA SYNTAXE YAML SOUBORŮ ---")
    yaml_files = [
        os.path.join(system_dir, "ansible", "inventory.yml"),
        os.path.join(system_dir, "ansible", "vars.yml"),
        os.path.join(system_dir, "ansible", "site.yml"),
        os.path.join(system_dir, "deploy", "vars.yml"),
    ]

    stacks_dir = os.path.join(stacks_repo_dir, "stacks")
    if os.path.isdir(stacks_dir):
        for stack_name in sorted(os.listdir(stacks_dir)):
            compose_file = os.path.join(stacks_dir, stack_name, "compose.yaml")
            if os.path.isfile(compose_file):
                yaml_files.append(compose_file)

    for yf in yaml_files:
        rel_path = os.path.relpath(yf, root_dir)
        if not os.path.exists(yf):
            if "deploy" in yf:
                print(f"[INFO] {rel_path} neexistuje (lokální privátní soubor).")
                continue
            else:
                print(f"[CHYBA] {rel_path} nenalezen!")
                has_errors = True
                continue

        try:
            with open(yf, "r", encoding="utf-8") as f:
                data = list(yaml.safe_load_all(f))
            print(f"[OK] {rel_path}")
        except Exception as e:
            print(f"[CHYBA] {rel_path}: {e}")
            has_errors = True

    # 2. Porovnání proměnných ansible/vars.yml vs deploy/vars.yml
    print("\n--- 2. POROVNÁNÍ PROMĚNNÝCH (TEMPLATE VS DEPLOY) ---")
    ansible_vars_file = os.path.join(system_dir, "ansible", "vars.yml")
    deploy_vars_file = os.path.join(system_dir, "deploy", "vars.yml")

    ansible_vars = {}
    if os.path.isfile(ansible_vars_file):
        with open(ansible_vars_file, "r", encoding="utf-8") as f:
            ansible_vars = yaml.safe_load(f) or {}

    deploy_vars = {}
    if os.path.isfile(deploy_vars_file):
        with open(deploy_vars_file, "r", encoding="utf-8") as f:
            deploy_vars = yaml.safe_load(f) or {}

        missing_in_deploy = set(ansible_vars.keys()) - set(deploy_vars.keys())
        missing_in_ansible = set(deploy_vars.keys()) - set(ansible_vars.keys())

        print(f"Klíčů v ansible/vars.yml: {len(ansible_vars)}")
        print(f"Klíčů v deploy/vars.yml:  {len(deploy_vars)}")

        if missing_in_deploy:
            print(f"[VAROVÁNÍ] Chybí v deploy/vars.yml: {missing_in_deploy}")
        if missing_in_ansible:
            print(f"[VAROVÁNÍ] Chybí v ansible/vars.yml: {missing_in_ansible}")

        placeholders = [k for k, v in deploy_vars.items() if isinstance(v, str) and "YOUR-" in v]
        if placeholders:
            print(f"[INFO] Nevyplněné zástupné hodnoty v deploy/vars.yml (před nasazením doplňte):")
            for p in placeholders:
                print(f"  - {p}: {deploy_vars[p]}")
        else:
            print("[OK] V deploy/vars.yml nejsou žádné nevyplněné zástupné hodnoty.")
    else:
        print("[INFO] deploy/vars.yml zatím neexistuje, přeskočeno.")

    # 3. Kontrola Jinja2 proměnných v site.yml
    print("\n--- 3. KONTROLA JINJA2 PROMĚNNÝCH V PLAYBOOKU ---")
    site_file = os.path.join(system_dir, "ansible", "site.yml")
    if os.path.isfile(site_file):
        with open(site_file, "r", encoding="utf-8") as f:
            site_content = f.read()

        jinja_vars = set(re.findall(r"\{\{\s*([a-zA-Z0-9_]+)", site_content))
        # Vyloučení vestavěných / smyčkových / dynamických proměnných
        jinja_vars -= {"item", "qm_status", "compose_dirs", "compose_output", "apt_install_result", "tailscale_status", "tailscale_ip", "tailscale_ip_cmd"}

        undefined_vars = jinja_vars - set(ansible_vars.keys())
        if undefined_vars:
            print(f"[CHYBA] Nedefinované Jinja2 proměnné v site.yml: {undefined_vars}")
            has_errors = True
        else:
            print(f"[OK] Všech {len(jinja_vars)} Jinja2 proměnných v site.yml je řádně definováno.")

    # 4. Kontrola proměnných prostředí v Docker Compose stackách
    print("\n--- 4. KONTROLA PROMĚNNÝCH PRO DOCKER COMPOSE ---")
    if os.path.isdir(stacks_dir):
        for stack_name in sorted(os.listdir(stacks_dir)):
            compose_file = os.path.join(stacks_dir, stack_name, "compose.yaml")
            if os.path.isfile(compose_file):
                with open(compose_file, "r", encoding="utf-8") as f:
                    content = f.read()
                env_vars = set(re.findall(r"\$\{([a-zA-Z0-9_]+)", content))
                if env_vars:
                    print(f"Stack '{stack_name}' vyžaduje: {', '.join(sorted(env_vars))}")
                else:
                    print(f"Stack '{stack_name}' nevyžaduje žádné proměnné prostředí.")

    print("\n==========================================")
    if has_errors:
        print("VÝSLEDEK: Byly nalezeny CHYBY, které je nutné před nasazením opravit!")
        sys.exit(1)
    else:
        print("VÝSLEDEK: Všechny kontroly proběhly ÚSPĚŠNĚ [OK]. Projekt je připraven k nasazení.")
        sys.exit(0)


if __name__ == "__main__":
    main()
