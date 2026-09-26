<#
.SYNOPSIS
    Kopíruje privátní konfiguraci (vars.yml), bootstrap skript a aktuální playbook na Proxmox VE server.
.PARAMETER ProxmoxHost
    IP adresa nebo hostname Proxmox serveru.
.EXAMPLE
    .\scp-deploy.ps1 -ProxmoxHost 10.154.10.x
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$ProxmoxHost
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VarsFile = Join-Path $ScriptDir "vars.yml"
$BootstrapFile = Join-Path $ScriptDir "bootstrap.sh"
$AnsibleDir = Join-Path (Split-Path -Parent $ScriptDir) "ansible"

if (-not (Test-Path $VarsFile)) {
    Write-Error "Soubor vars.yml nebyl nalezen v $ScriptDir!"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ProxmoxHost)) {
    $ProxmoxHost = Read-Host "Zadejte IP adresu nebo hostname Proxmox serveru"
}

if ([string]::IsNullOrWhiteSpace($ProxmoxHost)) {
    Write-Error "Nebyla zadána žádná IP adresa."
    exit 1
}

$RemoteDeployDir = "/opt/testudines-system/deploy"
$RemoteAnsibleDir = "/opt/testudines-system/ansible"

Write-Host "`n==> 1. Vytvářím adresáře na Proxmoxu ($ProxmoxHost)..." -ForegroundColor Cyan
ssh -o StrictHostKeyChecking=accept-new root@$ProxmoxHost "mkdir -p $RemoteDeployDir $RemoteAnsibleDir"

Write-Host "==> 2. Kopíruji vars.yml..." -ForegroundColor Cyan
scp $VarsFile "root@${ProxmoxHost}:${RemoteDeployDir}/vars.yml"

if (Test-Path $BootstrapFile) {
    Write-Host "==> 3. Kopíruji bootstrap.sh..." -ForegroundColor Cyan
    scp $BootstrapFile "root@${ProxmoxHost}:${RemoteDeployDir}/bootstrap.sh"
    ssh root@$ProxmoxHost "chmod +x ${RemoteDeployDir}/bootstrap.sh"
}

if (Test-Path $AnsibleDir) {
    Write-Host "==> 4. Kopíruji aktuální Ansible soubory (site.yml, vars.yml, inventory.yml)..." -ForegroundColor Cyan
    scp -r "$AnsibleDir/*" "root@${ProxmoxHost}:${RemoteAnsibleDir}/"
}

Write-Host "`n[HOTOVO] Konfigurace a soubory byly nahrány na Proxmox ($ProxmoxHost)." -ForegroundColor Green
Write-Host "Pro spuštění bootstrapu spusťte:" -ForegroundColor Yellow
Write-Host "  ssh root@$ProxmoxHost"
Write-Host "  cd /opt/testudines-system/deploy"
Write-Host "  bash bootstrap.sh`n"
