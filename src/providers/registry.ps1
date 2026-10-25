# Provider registry : écriture d'une valeur de registre.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'registry'

    Describe = {
        param($Action, $Context)
        "$($Action['path'])\$($Action['name']) = $($Action['value'])"
    }

    Test     = {
        param($Action, $Context)
        if (-not (Test-Path -Path $Action['path'])) { return $false }
        $key = Get-Item -Path $Action['path']
        if ($Action['name'] -notin $key.GetValueNames()) { return $false }
        $current = $key.GetValue($Action['name'], $null, 'DoNotExpandEnvironmentNames')
        if ($Action['type'] -eq 'MultiString') {
            return ((@($current) -join "`n") -ceq (@($Action['value']) -join "`n"))
        }
        "$current" -ceq "$($Action['value'])"
    }

    Read     = {
        param($Action, $Context)
        if (-not (Test-Path -Path $Action['path'])) { return [ordered]@{ exists = $false; keyExists = $false } }
        $key = Get-Item -Path $Action['path']
        if ($Action['name'] -notin $key.GetValueNames()) { return [ordered]@{ exists = $false; keyExists = $true } }
        [ordered]@{
            exists = $true
            type   = "$($key.GetValueKind($Action['name']))"
            value  = $key.GetValue($Action['name'], $null, 'DoNotExpandEnvironmentNames')
        }
    }

    Invoke   = {
        param($Action, $Context)
        if (-not (Test-Path -Path $Action['path'])) {
            New-Item -Path $Action['path'] -Force | Out-Null
        }
        New-ItemProperty -Path $Action['path'] -Name $Action['name'] -PropertyType $Action['type'] -Value $Action['value'] -Force | Out-Null
    }
}
