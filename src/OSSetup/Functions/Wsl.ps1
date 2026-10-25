function Get-OSSetupPhysicalMemoryGB {
    <#
    .SYNOPSIS
        Mémoire physique totale de la machine, en Go.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param()
    (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB
}

function Get-OSSetupWslMemoryLimit {
    <#
    .SYNOPSIS
        Plafond mémoire de la VM WSL 2 : un pourcentage de la RAM, borné pour rester valable sur toute machine
        (au moins 2 Go pour WSL, au moins 4 Go laissés à Windows). Retourne $null si la machine est trop petite
        pour ces deux bornes : WSL garde alors sa valeur par défaut (la moitié de la RAM).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [double]$PhysicalGB,

        [Parameter(Mandatory)]
        [ValidateRange(1, 100)]
        [int]$Percent
    )
    $minGB = 2
    $reserveGB = 4
    $maxGB = [math]::Floor($PhysicalGB) - $reserveGB
    if ($maxGB -lt $minGB) { return $null }
    $target = [math]::Floor($PhysicalGB * $Percent / 100)
    $value = [math]::Min([math]::Max($target, $minGB), $maxGB)
    [ordered]@{
        GB      = [int]$value
        Clamped = $value -ne $target
        Reason  = if ($value -gt $target) { "au moins $minGB Go pour WSL" } elseif ($value -lt $target) { "au moins $reserveGB Go laissés à Windows" } else { '' }
    }
}

function Get-OSSetupWslConfigValue {
    <#
    .SYNOPSIS
        Valeur à écrire pour une action wsl-config : value telle quelle, ou plafond calculé (memoryPercent) ;
        $null si rien ne doit être écrit. -Log signale dans le journal une valeur ramenée dans les bornes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action,

        [switch]$Log
    )
    if (-not $Action.Contains('memoryPercent')) { return $Action['value'] }
    $physicalGB = Get-OSSetupPhysicalMemoryGB
    $limit = Get-OSSetupWslMemoryLimit -PhysicalGB $physicalGB -Percent $Action['memoryPercent']
    if ($Log -and $null -eq $limit) {
        Write-OSSetupLog -Level Warning -Message ('  {0:N0} Go de RAM : pas de plafond pour WSL (valeur par défaut, la moitié de la RAM).' -f $physicalGB)
    }
    if ($null -eq $limit) { return $null }
    if ($Log -and $limit.Clamped) {
        Write-OSSetupLog -Level Warning -Message ('  {0} % de {1:N0} Go ramené à {2} Go ({3}).' -f $Action['memoryPercent'], $physicalGB, $limit.GB, $limit.Reason)
    }
    "$($limit.GB)GB"
}

function Get-OSSetupIniValue {
    <#
    .SYNOPSIS
        Valeur d'une clé dans une section d'un fichier INI (.wslconfig) ; $null si absente. Casse ignorée.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key
    )
    $current = $null
    foreach ($line in $Text -split '\r?\n') {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') { $current = $Matches[1].Trim(); continue }
        if ($current -eq $Section -and $line -match "^\s*$([regex]::Escape($Key))\s*=(.*)$") {
            return $Matches[1].Trim()
        }
    }
    $null
}

function Set-OSSetupIniValue {
    <#
    .SYNOPSIS
        Retourne le texte INI avec la clé réglée dans sa section : ligne remplacée si elle existe, ajoutée à la fin
        de la section sinon, section créée au besoin. Le reste du fichier (commentaires compris) est conservé.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Retourne un texte modifié, sans écrire de fichier.')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Section,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Value
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Text) { $lines.AddRange([string[]]($Text.TrimEnd("`r", "`n") -split '\r?\n')) }
    $entry = "$Key=$Value"
    $current = $null
    $lastInSection = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[([^\]]+)\]\s*$') {
            $current = $Matches[1].Trim()
            if ($current -eq $Section) { $lastInSection = $i }
            continue
        }
        if ($current -ne $Section) { continue }
        if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $lines[$i] = $entry
            return ($lines -join "`r`n") + "`r`n"
        }
        if ($lines[$i].Trim()) { $lastInSection = $i }
    }
    if ($lastInSection -ge 0) {
        $lines.Insert($lastInSection + 1, $entry)
    }
    else {
        if ($lines.Count -gt 0) { $lines.Add('') }
        $lines.Add("[$Section]")
        $lines.Add($entry)
    }
    ($lines -join "`r`n") + "`r`n"
}
