# Faits : informations détectées sur la machine, jamais demandées à l'utilisateur.
# Ils servent aux conditions « when » des éléments du catalogue.

$script:FactNames = @(
    'Platform', 'OSName', 'OSBuild', 'Edition', 'Activated', 'IsAdmin',
    'Manufacturer', 'Model', 'CpuVendor', 'GpuVendor', 'VirtualizationEnabled'
)

function Get-OSSetupFactName {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Le tableau est émis élément par élément : ce sont des chaînes.')]
    [OutputType([string])]
    param()
    $script:FactNames
}

function Get-OSSetupFact {
    <#
    .SYNOPSIS
        Détecte les faits de la machine courante.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    $facts = [ordered]@{}
    foreach ($name in $script:FactNames) { $facts[$name] = $null }
    $facts['Platform'] = Get-OSSetupPlatform
    $facts['IsAdmin'] = Test-OSSetupElevated
    if (-not $IsWindows) {
        return $facts
    }

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $facts['OSBuild'] = $build
    $facts['OSName'] = if ($build -ge 22000) { 'windows-11' } else { 'windows-10' }
    $facts['Edition'] = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID

    $license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" |
        Select-Object -First 1
    $facts['Activated'] = $null -ne $license -and $license.LicenseStatus -eq 1

    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $facts['Manufacturer'] = ConvertTo-OSSetupVendor -Name $computer.Manufacturer
    $facts['Model'] = $computer.Model

    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $facts['CpuVendor'] = ConvertTo-OSSetupVendor -Name $cpu.Manufacturer
    $facts['VirtualizationEnabled'] = [bool]$cpu.VirtualizationFirmwareEnabled -or [bool]$computer.HypervisorPresent

    # Plusieurs GPU possibles (ex. iGPU Intel + NVIDIA) : tableau dédoublonné.
    $facts['GpuVendor'] = @(Get-CimInstance -ClassName Win32_VideoController |
            ForEach-Object { ConvertTo-OSSetupVendor -Name $_.Name } |
            Where-Object { $_ -ne 'other' } |
            Select-Object -Unique)
    $facts
}

function ConvertTo-OSSetupVendor {
    <#
    .SYNOPSIS
        Normalise un nom de fabricant (ex. « GenuineIntel », « NVIDIA GeForce RTX 3070 ») en identifiant court.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Name
    )
    switch -Regex ($Name) {
        'nvidia' { return 'nvidia' }
        'amd|advanced micro devices|radeon' { return 'amd' }
        'intel' { return 'intel' }
        'dell' { return 'dell' }
        'lenovo' { return 'lenovo' }
        'hewlett|^hp' { return 'hp' }
        'microsoft' { return 'microsoft' }
        'gigabyte' { return 'gigabyte' }
        'asus' { return 'asus' }
        'micro-star|msi' { return 'msi' }
    }
    'other'
}

function Test-OSSetupItemApplicable {
    <#
    .SYNOPSIS
        Indique si un élément s'applique à la machine : plateforme supportée et condition « when » satisfaite.
    .DESCRIPTION
        Chaque clé de « when » est un fait ; la valeur attendue est une valeur ou une liste de valeurs acceptées.
        Si le fait est une liste (ex. GpuVendor), il suffit qu'une de ses valeurs soit acceptée.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Item,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Facts
    )
    if ($Facts['Platform'] -notin $Item['platforms']) { return $false }
    $when = $Item['when']
    if ($null -eq $when) { return $true }
    foreach ($name in $when.Keys) {
        $accepted = @($when[$name])
        $actual = @($Facts[$name])
        if (-not ($actual | Where-Object { $_ -in $accepted })) { return $false }
    }
    $true
}
