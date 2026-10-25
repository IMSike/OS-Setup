Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($file in Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*.ps1' | Sort-Object -Property Name) {
    . $file.FullName
}

# Chaque fichier de providers/ retourne une table { Name; Test; Invoke; Describe }.
$script:Providers = @{}
$providerRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\providers'
foreach ($file in Get-ChildItem -Path $providerRoot -Filter '*.ps1' | Sort-Object -Property Name) {
    $provider = & $file.FullName
    $script:Providers[$provider.Name] = $provider
}

function Get-OSSetupProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    if (-not $script:Providers.ContainsKey($Name)) {
        throw "Provider inconnu : '$Name'."
    }
    $script:Providers[$Name]
}
