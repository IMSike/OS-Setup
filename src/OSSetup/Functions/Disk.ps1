function Get-OSSetupSystemDisk {
    <#
    .SYNOPSIS
        Taille et espace libre (Go) du disque système, celui de Windows et des profils (Docker, WSL, caches).
    #>
    [CmdletBinding()]
    param()
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
    [pscustomobject]@{
        Drive  = $env:SystemDrive
        SizeGB = $disk.Size / 1GB
        FreeGB = $disk.FreeSpace / 1GB
    }
}

function Get-OSSetupDiskBoundedSize {
    <#
    .SYNOPSIS
        Taille plafonnée selon le disque : MaxGB, ramené à Percent % du disque si celui-ci est petit (au moins 1 Go).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [double]$DiskGB,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10000)]
        [int]$MaxGB,

        [Parameter(Mandatory)]
        [ValidateRange(1, 100)]
        [int]$Percent
    )
    $byDisk = [math]::Max([math]::Floor($DiskGB * $Percent / 100), 1)
    $value = [math]::Min($MaxGB, $byDisk)
    [ordered]@{ GB = [int]$value; Clamped = $value -lt $MaxGB }
}

function Get-OSSetupDockerBuildCacheLimit {
    <#
    .SYNOPSIS
        Plafond du cache de build Docker pour une action docker-build-cache, selon le disque système.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action
    )
    $diskGB = (Get-OSSetupSystemDisk).SizeGB
    $limit = Get-OSSetupDiskBoundedSize -DiskGB $diskGB -MaxGB $Action['maxGB'] -Percent $Action['diskPercent']
    $limit['DiskGB'] = $diskGB
    $limit
}

function Get-OSSetupDockerBuildCacheSetting {
    <#
    .SYNOPSIS
        Clés de daemon.json gérées par une action docker-build-cache : nettoyage automatique du cache au-delà du plafond.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action
    )
    $limit = Get-OSSetupDockerBuildCacheLimit -Action $Action
    [ordered]@{ builder = [ordered]@{ gc = [ordered]@{ enabled = $true; defaultKeepStorage = "$($limit.GB)GB" } } }
}

function Get-OSSetupLogonTaskArgument {
    <#
    .SYNOPSIS
        Arguments de powershell.exe pour une tâche logon-task : script lancé sans profil ni fenêtre.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Script
    )
    "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`""
}

function Write-OSSetupDiskSpaceWarning {
    <#
    .SYNOPSIS
        Avertit quand le disque système a peu d'espace libre : Docker, WSL et les navigateurs de Playwright peuvent le
        remplir. Avertissement seulement, rien n'est bloqué.
    #>
    [CmdletBinding()]
    param(
        [double]$MinFreeGB = 40
    )
    $disk = Get-OSSetupSystemDisk
    if ($disk.FreeGB -lt $MinFreeGB) {
        Write-OSSetupLog -Level Warning -Message ('Espace libre sur {0} : {1:N1} Go (moins de {2} Go). Docker, WSL et les navigateurs de Playwright peuvent remplir le disque : libérer de la place avant, ou ne pas les choisir.' -f $disk.Drive, $disk.FreeGB, $MinFreeGB)
    }
}
