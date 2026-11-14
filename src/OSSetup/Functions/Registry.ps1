# Fonctions d'appui du provider registry.

function ConvertTo-OSSetupRegistryNumber {
    <#
    .SYNOPSIS
        Ramène une valeur DWord ou QWord à une forme unique : signée (celle que lit et écrit le registre de PowerShell,
        ex. 0xFFFFFFFF = -1) ou non signée (-Unsigned, pour comparer). Accepte les deux formes en entrée.
    #>
    [CmdletBinding()]
    [OutputType([int], [long], [uint32], [uint64])]
    param(
        [Parameter(Mandatory)]
        $Value,

        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'QWord')]
        [string]$Type,

        [switch]$Unsigned
    )
    $range = if ($Type -eq 'DWord') { [decimal]4294967296 } else { [decimal]::Parse('18446744073709551616', [cultureinfo]::InvariantCulture) }
    $number = [decimal]$Value
    if ($number -ne [decimal]::Truncate($number) -or $number -lt (-$range / 2) -or $number -ge $range) {
        throw "Valeur $Type hors limites : $Value."
    }
    if ($number -lt 0) { $number += $range }
    if ($Unsigned) {
        if ($Type -eq 'DWord') { return [uint32]$number }
        return [uint64]$number
    }
    if ($number -ge $range / 2) { $number -= $range }
    if ($Type -eq 'DWord') { return [int]$number }
    [long]$number
}
