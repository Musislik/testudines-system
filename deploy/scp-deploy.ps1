<#
.SYNOPSIS
    Kopíruje pouze bootstrap skript a privátní konfiguraci (vars.yml) na Proxmox VE server.
.PARAMETER ProxmoxHost
    IP adresa nebo hostname Proxmox serveru.
.EXAMPLE
    .\scp-deploy.ps1 -ProxmoxHost 10.0.1.26
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

if (-not (Test-Path $VarsFile)) {
    Write-Error "Soubor vars.yml nebyl nalezen v $ScriptDir!"
    exit 1
}

if (-not (Test-Path $BootstrapFile)) {
    Write-Error "Soubor bootstrap.sh nebyl nalezen v $ScriptDir!"
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

Write-Host "`n==> 1. Příprava adresáře na Proxmoxu ($RemoteDeployDir)..." -ForegroundColor Cyan
ssh -o StrictHostKeyChecking=accept-new root@$ProxmoxHost "mkdir -p $RemoteDeployDir"

Write-Host "==> 2. Kopíruji vars.yml..." -ForegroundColor Cyan
scp $VarsFile "root@${ProxmoxHost}:${RemoteDeployDir}/vars.yml"

Write-Host "==> 3. Kopíruji bootstrap.sh..." -ForegroundColor Cyan
scp $BootstrapFile "root@${ProxmoxHost}:${RemoteDeployDir}/bootstrap.sh"
ssh root@$ProxmoxHost "chmod +x ${RemoteDeployDir}/bootstrap.sh"

Write-Host "`n[HOTOVO] bootstrap.sh a vars.yml byly úspěšně nahrány na Proxmox ($ProxmoxHost)." -ForegroundColor Green
Write-Host "Pro spuštění bootstrapu spusťte:" -ForegroundColor Yellow
Write-Host "  ssh root@$ProxmoxHost"
Write-Host "  cd /opt/testudines-system/deploy"
Write-Host "  bash bootstrap.sh`n"
