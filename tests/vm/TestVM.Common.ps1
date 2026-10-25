# Fonctions partagées par les scripts de VM de test (dot-sourcé).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Compte de la VM de test. Mot de passe volontairement fixe et public : il ne protège qu'une VM jetable,
# locale, sans accès distant. PowerShell Direct refuse les comptes sans mot de passe.
$script:TestUserName = 'tester'
$script:TestPassword = 'OSSetup-Test'
$script:BaselineCheckpoint = 'vierge'
# Point de contrôle pris après le bootstrap (winget, Git, PowerShell 7 installés) : tests plus rapides.
$script:PrerequisiteCheckpoint = 'prerequis'
$script:GuestRepoRoot = 'C:\OS-Setup'
# Dossier de la VM hors dépôt : trace du bootstrap (state\bootstrap.json) et empreinte de bootstrap.ps1 du
# point de contrôle « prerequis ».
$script:GuestTestRoot = 'C:\OSSetup-Tests'

function Get-TestVMCredential {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Mot de passe public d''une VM de test jetable.')]
    [CmdletBinding()]
    [OutputType([pscredential])]
    param()
    [pscredential]::new($script:TestUserName, (ConvertTo-SecureString -String $script:TestPassword -AsPlainText -Force))
}

function Get-TestVMRoot {
    # Dossier de travail hors dépôt (images, disques virtuels) : plusieurs dizaines de Go.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    Join-Path -Path $env:ProgramData -ChildPath 'OSSetup-Tests'
}

function Assert-TestVMAdministrator {
    <#
    .SYNOPSIS
        Vérifie les droits nécessaires. -HyperVOnly : l'appartenance au groupe « Administrateurs Hyper-V »
        suffit (piloter les VM), sans invite UAC. Sinon : administrateur requis (disques virtuels, DISM).
    #>
    [CmdletBinding()]
    param([switch]$HyperVOnly)
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    # S-1-5-32-578 = « Administrateurs Hyper-V », identifiant indépendant de la langue.
    if ($HyperVOnly -and $principal.IsInRole([Security.Principal.SecurityIdentifier]::new('S-1-5-32-578'))) { return }
    if ($HyperVOnly) {
        throw "Droits insuffisants : lancer en administrateur, ou ajouter le compte au groupe « Administrateurs Hyper-V » (puis se reconnecter)."
    }
    throw 'Ce script doit être lancé en administrateur (disques virtuels, DISM).'
}

function Write-TestVMStep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host -Object ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message) -ForegroundColor Cyan
}

function Set-TestVMHostAwake {
    <#
    .SYNOPSIS
        Empêche (ou ré-autorise) la mise en veille de l'hôte pendant un test, pour le thread courant.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][bool]$Enabled)
    if (-not ('OSSetupTests.Power' -as [type])) {
        Add-Type -Namespace OSSetupTests -Name Power -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
    }
    # ES_CONTINUOUS = 0x80000000, ES_SYSTEM_REQUIRED = 0x1
    $flags = if ($Enabled) { [uint32]'0x80000001' } else { [uint32]'0x80000000' }
    if ($PSCmdlet.ShouldProcess('hôte', "Maintien en éveil : $Enabled")) {
        [void][OSSetupTests.Power]::SetThreadExecutionState($flags)
    }
}

function Wait-TestVMReady {
    <#
    .SYNOPSIS
        Attend que la VM accepte PowerShell Direct et que la session de l'utilisateur de test soit ouverte.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutMinutes = 30
    )
    $credential = Get-TestVMCredential
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        try {
            # Session stable : explorer.exe lancé depuis au moins 30 s (il redémarre parfois juste après l'ouverture).
            $ready = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ScriptBlock {
                $explorer = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
                $explorer -and ((Get-Date) - $explorer.StartTime).TotalSeconds -ge 30
            }
            if ($ready) { return }
        }
        catch {
            Write-Verbose -Message $_.Exception.Message
        }
        Start-Sleep -Seconds 10
    }
    throw "La VM '$Name' n'est pas prête après $TimeoutMinutes minutes."
}
