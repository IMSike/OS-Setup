#Requires -Version 7.4
<#
.SYNOPSIS
    Crée (ou recrée) le point de contrôle « prerequis » : la VM après le bootstrap (winget, Git et PowerShell 7
    installés), session ouverte. Les tests qui en repartent économisent 3 à 4 minutes.
.DESCRIPTION
    1. Retour à « vierge », attente de la fin de la première ouverture de session.
    2. Bootstrap réel (Invoke-TestVM.ps1), suivi d'une simple simulation du setup (-WhatIf) : rien n'est modifié
       au-delà des outils du bootstrap.
    3. La trace du bootstrap (state\bootstrap.json : outils qu'il a installés) et l'empreinte de bootstrap.ps1 sont
       mises de côté hors du dépôt (C:\OSSetup-Tests), le dépôt copié est supprimé.
    4. Point de contrôle pris VM allumée : sa restauration redonne une session ouverte, sans démarrage.
    À relancer quand bootstrap.ps1 change (Invoke-TestVM.ps1 le signale).
    À lancer en administrateur, ou depuis un compte membre du groupe « Administrateurs Hyper-V ».
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = 'OSSetup-Win10'
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'TestVM.Common.ps1')
Assert-TestVMAdministrator -HyperVOnly
$credential = Get-TestVMCredential

& (Join-Path -Path $PSScriptRoot -ChildPath 'Reset-TestVM.ps1') -Name $Name -Checkpoint $script:BaselineCheckpoint
if ((Get-VM -Name $Name).State -ne 'Running') { Start-VM -Name $Name }
Write-TestVMStep 'Attente de la fin de la première ouverture de session'
Wait-TestVMReady -Name $Name
$deadline = (Get-Date).AddMinutes(15)
while ((Get-Date) -lt $deadline) {
    $busy = Invoke-Command -VMName $Name -Credential $credential -ScriptBlock { [bool](Get-Process -Name FirstLogonAnim -ErrorAction SilentlyContinue) }
    if (-not $busy) { break }
    Start-Sleep -Seconds 10
}
Start-Sleep -Seconds 30

Write-TestVMStep 'Bootstrap (outils du setup), puis simulation du setup'
& (Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-TestVM.ps1') -Name $Name -SetupArguments '-Profiles', 'base', '-AcceptDefaults', '-WhatIf'
if ($LASTEXITCODE -ne 0) { throw "Le bootstrap a échoué dans la VM (code $LASTEXITCODE) : point de contrôle non créé." }

$repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$hash = (Get-FileHash -Path (Join-Path -Path $repoRoot -ChildPath 'bootstrap.ps1') -Algorithm SHA256).Hash
Invoke-Command -VMName $Name -Credential $credential -ArgumentList $script:GuestRepoRoot, $script:GuestTestRoot, $hash -ScriptBlock {
    param($RepoRoot, $TestRoot, $Hash)
    $trace = Join-Path -Path $RepoRoot -ChildPath 'state\bootstrap.json'
    if (-not (Test-Path -Path $trace)) { throw 'Trace du bootstrap (state\bootstrap.json) introuvable.' }
    $tools = (Get-Content -Path $trace -Raw | ConvertFrom-Json).installedTools
    if (@($tools).Count -lt 2) { throw "Le bootstrap n'a pas installé ses outils ($($tools -join ', ')) : la VM n'était pas vierge ?" }
    New-Item -Path $TestRoot -ItemType Directory -Force | Out-Null
    Copy-Item -Path $trace -Destination $TestRoot -Force
    Set-Content -Path (Join-Path -Path $TestRoot -ChildPath 'bootstrap.sha256') -Value $Hash
    Remove-Item -Path $RepoRoot -Recurse -Force
    "Outils du bootstrap : $($tools -join ', ')"
}

if ($PSCmdlet.ShouldProcess($Name, "Créer le point de contrôle « $script:PrerequisiteCheckpoint »")) {
    Get-VMSnapshot -VMName $Name -Name $script:PrerequisiteCheckpoint -ErrorAction SilentlyContinue | Remove-VMSnapshot
    Checkpoint-VM -Name $Name -SnapshotName $script:PrerequisiteCheckpoint
    Write-TestVMStep "Point de contrôle « $script:PrerequisiteCheckpoint » créé"
}
