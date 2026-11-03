# Fonctions d'appui des providers système (service, scheduled-task, power).

# Paramètres d'alimentation pris en charge : alias powercfg (sous-groupe, paramètre), valeurs en secondes.
$script:PowerSettings = @{
    standby   = @('SUB_SLEEP', 'STANDBYIDLE')
    hibernate = @('SUB_SLEEP', 'HIBERNATEIDLE')
    display   = @('SUB_VIDEO', 'VIDEOIDLE')
}

# Listes d'état longues à lire, lues une fois par passe, effacées avant et après chaque action exécutée : listes DISM
# complètes (paquets provisionnés, capacités Windows ; session Windows PowerShell 5.1 sous le PowerShell 7 du Store)
# et tâches planifiées (une lecture de toutes les tâches coûte autant qu'une lecture par nom).
$script:StateCache = @{}

function Import-OSSetupCompatibilityModule {
    <#
    .SYNOPSIS
        Charge un module par Windows PowerShell 5.1 (-UseWindowsPowerShell, objets désérialisés), même sous -WhatIf.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    # Sous -WhatIf, la création du module de compatibilité (copie de fichiers temporaires) serait elle aussi
    # simulée et le module ne se chargerait pas. Elle s'exécute hors de cette fonction, d'où la préférence
    # globale, rétablie ensuite. Charger un module ne modifie pas le système.
    $savedWhatIf = $global:WhatIfPreference
    $global:WhatIfPreference = $false
    try {
        Import-Module -Name $Name -UseWindowsPowerShell -Global -WarningAction SilentlyContinue -ErrorAction Stop
    }
    finally {
        $global:WhatIfPreference = $savedWhatIf
    }
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
        Import-OSSetupCompatibilityModule -Name Appx
    }
}

function Import-OSSetupDismModule {
    <#
    .SYNOPSIS
        Charge le module Dism. Dans le PowerShell 7 du Store (processus empaqueté), l'API DISM ne peut pas créer sa
        session (« Classe non enregistrée », après deux minutes d'attente) : il passe alors par Windows PowerShell 5.1.
    #>
    [CmdletBinding()]
    param()
    if (Get-Module -Name Dism) { return }
    if ($PSHOME -notlike '*\WindowsApps\*') {
        Import-Module -Name Dism -Global -ErrorAction Stop
        return
    }
    Import-OSSetupCompatibilityModule -Name Dism
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
    if ($elevated) { Import-OSSetupDismModule }
    $provisioned = @(if ($elevated) {
            Get-OSSetupProvisionedPackage | Where-Object { $_.DisplayName -eq $Name } | ForEach-Object { $_.PackageName }
        })
    [pscustomobject]@{ Installed = @($installed); Provisioned = @($provisioned) }
}

function Get-OSSetupProvisionedPackage {
    <#
    .SYNOPSIS
        Paquets provisionnés (DisplayName, PackageName), lus une fois par passe (cache vidé par Clear-OSSetupStateCache).
        Lecture admin uniquement.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:StateCache.ContainsKey('ProvisionedPackages')) {
        Import-OSSetupDismModule
        $script:StateCache['ProvisionedPackages'] = @(Get-AppxProvisionedPackage -Online |
                ForEach-Object { [pscustomobject]@{ DisplayName = [string]$_.DisplayName; PackageName = [string]$_.PackageName } })
    }
    $script:StateCache['ProvisionedPackages']
}

function Get-OSSetupWindowsCapabilityList {
    <#
    .SYNOPSIS
        Capacités Windows (Name, State), lues une fois par passe (cache vidé par Clear-OSSetupStateCache). Lecture
        admin uniquement.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:StateCache.ContainsKey('WindowsCapabilities')) {
        Import-OSSetupDismModule
        $script:StateCache['WindowsCapabilities'] = @(Get-WindowsCapability -Online |
                ForEach-Object { [pscustomobject]@{ Name = [string]$_.Name; State = [string]$_.State } })
    }
    $script:StateCache['WindowsCapabilities']
}

function Get-OSSetupWindowsCapabilityMatch {
    <#
    .SYNOPSIS
        Capacités Windows dont le nom, sans version, correspond (« Browser.InternetExplorer », « Hello.Face.* »).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    Get-OSSetupWindowsCapabilityList | Where-Object { $_.Name -like "$Name~*" }
}

function Clear-OSSetupStateCache {
    <#
    .SYNOPSIS
        Oublie les listes d'état lues (paquets provisionnés, capacités Windows, tâches planifiées) : appelé au début
        de chaque passe et autour de chaque action exécutée, pour que les vérifications relisent l'état réel.
    #>
    [CmdletBinding()]
    param()
    $script:StateCache.Clear()
}

function Get-OSSetupScheduledTask {
    <#
    .SYNOPSIS
        Tâche planifiée par son nom (et son dossier), d'après la liste de toutes les tâches lue une fois par passe
        (cache vidé par Clear-OSSetupStateCache). Rien si elle n'existe pas.
    .DESCRIPTION
        Pour les tests de présence des providers : Get-ScheduledTask coûte environ 0,4 s par appel, qu'il lise une
        tâche ou toutes. Une attente qui suit l'état d'une tâche en cours appelle Get-ScheduledTask directement.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        # Dossier de la tâche (ex. « \Microsoft\Windows\Autochk\ ») ; sans lui, tous les dossiers.
        [string]$TaskPath
    )
    if (-not $script:StateCache.ContainsKey('ScheduledTasks')) {
        $script:StateCache['ScheduledTasks'] = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    }
    $script:StateCache['ScheduledTasks'] | Where-Object { $_.TaskName -eq $TaskName -and (-not $TaskPath -or $_.TaskPath -eq $TaskPath) }
}

function Get-OSSetupStoreCancelScript {
    <#
    .SYNOPSIS
        Script Windows PowerShell 5.1 qui annule les mises à jour du Store en attente d'une application et écrit les
        identifiants de produit annulés.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[\w.-]+$')]
        [string]$Name
    )
    # Le nom d'assembly qui suit le type est ignoré par la résolution WinRT (seul l'espace de noms compte) : il est
    # aligné sur StoreUpdate.User.ps1 par simple cohérence. En cas d'échec, seul le message de l'exception est écrit
    # sur la sortie d'erreur (sinon Windows PowerShell la met en forme sur plusieurs lignes coupées), code de sortie 1.
    @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
try {
    [void][Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager, Windows.ApplicationModel.Store.Preview, ContentType = WindowsRuntime]
    `$manager = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager]::new()
    foreach (`$item in @(`$manager.AppInstallItems | Where-Object { `$_.PackageFamilyName -like '$($Name)_*' })) {
        `$manager.Cancel(`$item.ProductId)
        `$item.ProductId
    }
}
catch {
    [Console]::Error.WriteLine(`$_.Exception.Message)
    exit 1
}
"@
}

function Invoke-OSSetupWindowsPowerShell {
    <#
    .SYNOPSIS
        Exécute un script dans Windows PowerShell 5.1 et retourne sa sortie, ses erreurs et son code de sortie.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Script
    )
    $powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $all = @(& $powershell -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1)
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        Output   = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        Errors   = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ })
        ExitCode = $exitCode
    }
}

function Test-OSSetupAppxInstalled {
    <#
    .SYNOPSIS
        Vrai si le paquet appx est installé pour le compte courant (une application du Store s'installe par compte).
    .DESCRIPTION
        Sert à juger la présence d'une application installée depuis la source msstore : `winget list --id <produit>`
        rattache aussi un MSI au produit du Store (ex. PowerShell 7-x64 et 9MZ1SNWT0N5D), même avec --source msstore.
        Ne lit pas les paquets provisionnés (DISM), contrairement à Get-OSSetupAppxPresence.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    Import-OSSetupAppxModule
    @(Get-AppxPackage -Name $Name).Count -gt 0
}

function Stop-OSSetupStoreUpdate {
    <#
    .SYNOPSIS
        Annule les téléchargements et mises à jour en attente du Store pour une application, avant sa suppression :
        sinon la mise à jour en cours s'achève après la suppression et réinstalle (et reprovisionne) l'application.
        Retourne les identifiants de produit annulés. Un échec de l'annulation est journalisé sans bloquer la suppression.
    .NOTES
        L'API de la file du Store (WinRT AppInstallManager) n'est pas accessible depuis PowerShell 7 : elle passe
        par Windows PowerShell 5.1.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[\w.-]+$')]
        [string]$Name
    )
    if (-not $PSCmdlet.ShouldProcess($Name, 'Annuler les mises à jour du Store en attente')) { return }
    $result = Invoke-OSSetupWindowsPowerShell -Script (Get-OSSetupStoreCancelScript -Name $Name)
    # Le script s'arrête à la première erreur (code de sortie 1) : le code de sortie suffit à détecter l'échec ; la
    # sortie d'erreur ne sert qu'au message (elle peut contenir du bruit sans échec, ou du CLIXML).
    if ($result.ExitCode -ne 0) {
        $detail = (@($result.Errors | ForEach-Object {
                    $text = [string]$_
                    if ($text -match '<S S="Error">') {
                        [regex]::Matches($text, '<S S="Error">(.*?)</S>') | ForEach-Object { $_.Groups[1].Value -replace '_x000D__x000A_', ' ' }
                    }
                    elseif ($text -notlike '#< CLIXML*') { $text }
                }) | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' '
        if (-not $detail) { $detail = "code de sortie $($result.ExitCode)" }
        Write-OSSetupLog -Level Warning -Message "  annulation des mises à jour du Store impossible pour $Name ($detail) : l'application peut revenir après un redémarrage"
    }
    $result.Output | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Unique
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

function Get-OSSetupUninstallEntryLocation {
    <#
    .SYNOPSIS
        Dossier d'installation d'une entrée « Programmes et fonctionnalités », ou $null s'il est inconnu.
    .DESCRIPTION
        InstallLocation de l'entrée s'il est renseigné. Le MSI de PowerShell le laisse vide, mais enregistre son
        dossier avec son code produit sous HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions : le code
        produit de l'entrée (nom de sa clé, ou commande msiexec) y retrouve le dossier.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Entry
    )
    if ($Entry.PSObject.Properties['InstallLocation'] -and $Entry.InstallLocation) { return [string]$Entry.InstallLocation }
    $productCode = $null
    if ($Entry.PSObject.Properties['PSChildName'] -and $Entry.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
        $productCode = $Entry.PSChildName
    }
    elseif ($Entry.PSObject.Properties['UninstallString'] -and $Entry.UninstallString -match '(?i)msiexec(\.exe)?\s+/[IX]\s*(\{[0-9A-F-]+\})') {
        $productCode = $Matches[2]
    }
    if (-not $productCode) { return $null }
    foreach ($version in @(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions\*' -ErrorAction SilentlyContinue)) {
        if ($version.PSObject.Properties['ProductCode'] -and $version.ProductCode -eq $productCode) {
            foreach ($name in 'InstallLocation', 'InstallDir') {
                if ($version.PSObject.Properties[$name] -and $version.$name) { return [string]$version.$name }
            }
        }
    }
    $null
}

function Test-OSSetupUninstallEntryHostsSetup {
    <#
    .SYNOPSIS
        Vrai si l'entrée « Programmes et fonctionnalités » est le PowerShell qui exécute le setup : la désinstaller
        maintenant arrêterait le setup en cours (ex. MSI de PowerShell 7 sur un ancien poste).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        $Entry,

        # Dossier du PowerShell qui exécute le setup.
        [string]$PowerShellHome = $PSHOME
    )
    # Le PowerShell du Store ne figure pas dans « Programmes et fonctionnalités ».
    if (-not $PowerShellHome -or $PowerShellHome -like '*\WindowsApps\*') { return $false }
    $location = Get-OSSetupUninstallEntryLocation -Entry $Entry
    if (-not $location) { return $false }
    $location = [IO.Path]::GetFullPath($location).TrimEnd('\')
    $current = [IO.Path]::GetFullPath($PowerShellHome).TrimEnd('\')
    $current -ieq $location -or $current.StartsWith("$location\", [StringComparison]::OrdinalIgnoreCase)
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
