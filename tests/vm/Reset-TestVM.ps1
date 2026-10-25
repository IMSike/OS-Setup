#Requires -Version 7.4
<#
.SYNOPSIS
    Ramène la VM de test à un point de contrôle : « vierge » (Windows fraîchement installé, par défaut) ou
    « prerequis » (après le bootstrap : winget, Git et PowerShell 7 installés, voir New-TestVMPrerequisite.ps1).
    À lancer en administrateur, ou depuis un compte membre du groupe « Administrateurs Hyper-V ».
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = 'OSSetup-Win10',

    [ValidateSet('vierge', 'prerequis')]
    [string]$Checkpoint = 'vierge'
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'TestVM.Common.ps1')
Assert-TestVMAdministrator -HyperVOnly

$snapshot = Get-VMSnapshot -VMName $Name -Name $Checkpoint -ErrorAction SilentlyContinue
if (-not $snapshot) {
    $hint = if ($Checkpoint -eq $script:PrerequisiteCheckpoint) { 'le créer avec New-TestVMPrerequisite.ps1' } else { 'créer la VM avec New-TestVM.ps1' }
    throw "Point de contrôle « $Checkpoint » introuvable pour la VM '$Name' ($hint)."
}

if ($PSCmdlet.ShouldProcess($Name, "Revenir au point de contrôle « $Checkpoint »")) {
    Write-TestVMStep "Retour de '$Name' à l'état « $Checkpoint »"
    Stop-VM -Name $Name -TurnOff -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    Restore-VMSnapshot -VMSnapshot $snapshot -Confirm:$false
}
