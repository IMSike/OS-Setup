# Fonctions d'appui des providers système (service, scheduled-task, power).

# Paramètres d'alimentation pris en charge : alias powercfg (sous-groupe, paramètre), valeurs en secondes.
$script:PowerSettings = @{
    standby   = @('SUB_SLEEP', 'STANDBYIDLE')
    hibernate = @('SUB_SLEEP', 'HIBERNATEIDLE')
    display   = @('SUB_VIDEO', 'VIDEOIDLE')
}

function Import-OSSetupAppxModule {
    <#
    .SYNOPSIS
        Charge le module Appx. Sous PowerShell 7 et Windows 10, il ne se charge pas nativement (« Operation is not
        supported on this platform ») : il passe alors par Windows PowerShell 5.1 (-UseWindowsPowerShell).
    #>
    [CmdletBinding()]
    param()
    if (Get-Module -Name Appx) { return }
    try {
        Import-Module -Name Appx -Global -ErrorAction Stop
    }
    catch {
        # Sous -WhatIf, la création du module de compatibilité (copie de fichiers temporaires) serait elle aussi
        # simulée et le module ne se chargerait pas. Elle s'exécute hors de cette fonction, d'où la préférence
        # globale, rétablie ensuite. Charger un module ne modifie pas le système.
        $savedWhatIf = $global:WhatIfPreference
        $global:WhatIfPreference = $false
        try {
            Import-Module -Name Appx -UseWindowsPowerShell -Global -WarningAction SilentlyContinue -ErrorAction Stop
        }
        finally {
            $global:WhatIfPreference = $savedWhatIf
        }
    }
}

function Test-OSSetupStorePowerShell {
    <#
    .SYNOPSIS
        Vrai si ce dossier de PowerShell ($PSHOME) est celui du paquet du Store (MSIX, sous WindowsApps).
    .DESCRIPTION
        Le Store met ce paquet à jour seul et ferme alors de force tous ses processus pwsh.exe (shells des terminaux et
        des volets herdr, agents lancés dedans). Le setup installe PowerShell 7 en MSI et supprime ce paquet : il ne doit
        donc pas tourner dedans.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$PowerShellHome
    )
    $PowerShellHome -match '\\WindowsApps\\'
}

function Get-OSSetupAppxPresence {
    <#
    .SYNOPSIS
        Où une application du Store est encore présente : installée (pour tous les comptes si élevé, sinon pour le
        compte courant) et provisionnée (installée d'office pour les nouveaux comptes ; lecture admin uniquement).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    Import-OSSetupAppxModule
    $elevated = Test-OSSetupElevated
    $installed = @(if ($elevated) { Get-AppxPackage -Name $Name -AllUsers } else { Get-AppxPackage -Name $Name }) |
        ForEach-Object { [string]$_.PackageFullName } | Select-Object -Unique
    $provisioned = @(if ($elevated) {
            Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $Name } | ForEach-Object { [string]$_.PackageName }
        })
    [pscustomobject]@{ Installed = @($installed); Provisioned = @($provisioned) }
}

function Get-OSSetupUninstallEntry {
    <#
    .SYNOPSIS
        Entrées « Programmes et fonctionnalités » (machine 64/32 bits et compte courant) dont le nom correspond
        (caractères génériques acceptés).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $entry = Get-ItemProperty -Path $_.PSPath
            if ($entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -like $DisplayName) { $entry }
        }
    }
}

function Wait-OSSetupUninstallEntryRemoval {
    <#
    .SYNOPSIS
        Attend que le logiciel disparaisse de « Programmes et fonctionnalités » ; $true s'il a disparu à temps.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [int]$TimeoutSeconds = 60
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (-not (Get-OSSetupUninstallEntry -DisplayName ([WildcardPattern]::Escape($DisplayName)))) { return $true }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    $false
}

function ConvertTo-OSSetupUninstallCommand {
    <#
    .SYNOPSIS
        Transforme la commande de désinstallation d'une entrée en { FilePath; Arguments } exécutable sans
        interaction : désinstallation MSI silencieuse, sinon commande silencieuse déclarée, sinon commande
        ordinaire complétée par les arguments du catalogue.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Entry,

        [string]$Arguments
    )
    $raw = if ($Entry.PSObject.Properties['QuietUninstallString'] -and $Entry.QuietUninstallString) { $Entry.QuietUninstallString } else { $Entry.UninstallString }
    if (-not $raw) { throw "Aucune commande de désinstallation pour « $($Entry.DisplayName) »." }
    if ($raw -match '(?i)msiexec(\.exe)?\s+/[IX]\s*(\{[0-9A-F-]+\})') {
        return [pscustomobject]@{ FilePath = 'msiexec.exe'; Arguments = "/x $($Matches[2]) /qn /norestart" }
    }
    if ($raw -match '^\s*"([^"]+)"\s*(.*)$' -or $raw -match '^\s*(\S+)\s*(.*)$') {
        $arguments = (@($Matches[2].Trim(), $Arguments) | Where-Object { $_ }) -join ' '
        return [pscustomobject]@{ FilePath = $Matches[1]; Arguments = $arguments }
    }
    throw "Commande de désinstallation illisible : $raw"
}

function Get-OSSetupStartupEntry {
    <#
    .SYNOPSIS
        Entrées de lancement à l'ouverture de session (clés Run) dont le nom correspond, avec leur état dans
        StartupApproved (ce qu'affiche le Gestionnaire des tâches). Premier octet impair = désactivée.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [ValidateSet('user', 'machine')]
        [string]$Scope = 'user'
    )
    $sources = if ($Scope -eq 'machine') {
        @(
            @{ Run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
            @{ Run = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
        )
    }
    else {
        @(@{ Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' })
    }
    foreach ($source in $sources) {
        if (-not (Test-Path -Path $source.Run)) { continue }
        $runKey = Get-Item -Path $source.Run
        $approvedKey = if (Test-Path -Path $source.Approved) { Get-Item -Path $source.Approved } else { $null }
        foreach ($valueName in $runKey.GetValueNames() | Where-Object { $_ -like $Name }) {
            # Affectation directe : « $x = if (...) { tableau } » déroulerait les octets en tableau d'objets.
            $state = $null
            if ($approvedKey) { $state = $approvedKey.GetValue($valueName, $null) }
            $enabled = -not ($state -is [byte[]] -and $state.Length -gt 0 -and ($state[0] -band 1) -eq 1)
            [pscustomobject]@{ Name = $valueName; Enabled = $enabled; ApprovedKey = $source.Approved }
        }
    }
}

function Disable-OSSetupStartupEntry {
    <#
    .SYNOPSIS
        Marque une entrée de démarrage « désactivée » comme le Gestionnaire des tâches : 03 00 00 00 suivi de la date
        de désactivation (FILETIME).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        $Entry
    )
    $value = [byte[]](@(3, 0, 0, 0) + [System.BitConverter]::GetBytes((Get-Date).ToFileTime()))
    if ($PSCmdlet.ShouldProcess($Entry.Name, 'Désactiver le lancement à l''ouverture de session')) {
        if (-not (Test-Path -Path $Entry.ApprovedKey)) { New-Item -Path $Entry.ApprovedKey -Force | Out-Null }
        New-ItemProperty -Path $Entry.ApprovedKey -Name $Entry.Name -PropertyType Binary -Value $value -Force | Out-Null
    }
}

function Split-OSSetupTaskPath {
    <#
    .SYNOPSIS
        Sépare le chemin complet d'une tâche planifiée (\Dossier\Nom) en dossier (\Dossier\) et nom.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Task
    )
    $index = $Task.LastIndexOf('\')
    $path = if ($index -le 0) { '\' } else { $Task.Substring(0, $index + 1) }
    $path
    $Task.Substring($index + 1)
}

function Format-OSSetupDuration {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int]$Seconds
    )
    $minutes = [math]::Floor($Seconds / 60)
    $rest = $Seconds % 60
    if ($minutes -eq 0) { return "$rest s" }
    if ($rest -eq 0) { return "$minutes min" }
    "$minutes min $rest s"
}

function ConvertFrom-OSSetupPowerQuery {
    <#
    .SYNOPSIS
        Extrait les index actuels (secteur, batterie) de la sortie de « powercfg /query » : ce sont les deux
        dernières valeurs hexadécimales, quelle que soit la langue.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Output
    )
    $values = @($Output | ForEach-Object { if ($_ -match ':\s*0x([0-9a-fA-F]+)\s*$') { [Convert]::ToInt64($Matches[1], 16) } })
    if ($values.Count -lt 2) { throw 'Sortie de powercfg inattendue : index actuels introuvables.' }
    @{ ac = $values[-2]; dc = $values[-1] }
}

function Get-OSSetupPowerValue {
    <#
    .SYNOPSIS
        Valeur actuelle (secondes) d'un paramètre d'alimentation du mode actif.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('standby', 'hibernate', 'display')]
        [string]$Setting,

        [Parameter(Mandatory)]
        [ValidateSet('ac', 'dc')]
        [string]$Source
    )
    $subgroup, $alias = $script:PowerSettings[$Setting]
    $output = & powercfg.exe /query SCHEME_CURRENT $subgroup $alias
    if ($LASTEXITCODE -ne 0) { throw "powercfg /query a échoué (code $LASTEXITCODE)." }
    (ConvertFrom-OSSetupPowerQuery -Output $output)[$Source]
}

function Set-OSSetupPowerValue {
    <#
    .SYNOPSIS
        Règle un paramètre d'alimentation du mode actif, puis le réactive pour appliquer la valeur.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('standby', 'hibernate', 'display')]
        [string]$Setting,

        [Parameter(Mandatory)]
        [ValidateSet('ac', 'dc')]
        [string]$Source,

        [Parameter(Mandatory)]
        [int]$Seconds
    )
    $subgroup, $alias = $script:PowerSettings[$Setting]
    if ($PSCmdlet.ShouldProcess("$Setting ($Source)", "Régler à $Seconds s")) {
        & powercfg.exe "/set$($Source)valueindex" SCHEME_CURRENT $subgroup $alias $Seconds
        if ($LASTEXITCODE -ne 0) { throw "powercfg /set$($Source)valueindex a échoué (code $LASTEXITCODE)." }
        & powercfg.exe /setactive SCHEME_CURRENT
        if ($LASTEXITCODE -ne 0) { throw "powercfg /setactive a échoué (code $LASTEXITCODE)." }
    }
}
