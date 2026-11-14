# Provider registry : écriture d'une valeur de registre.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'registry'

    Describe = {
        param($Action, $Context)
        "$($Action['path'])\$($Action['name']) = $($Action['value'])"
    }

    # Conforme seulement avec le type attendu (une chaîne « 0 » n'est pas le DWord 0) et la valeur attendue. DWord et
    # QWord sont comparés non signés : le registre les rend signés (0xFFFFFFFF relu -1), le catalogue peut les écrire
    # dans l'une ou l'autre forme.
    Test     = {
        param($Action, $Context)
        if (-not (Test-Path -Path $Action['path'])) { return $false }
        $key = Get-Item -Path $Action['path']
        if ($Action['name'] -notin $key.GetValueNames()) { return $false }
        if ("$($key.GetValueKind($Action['name']))" -ne $Action['type']) { return $false }
        $current = $key.GetValue($Action['name'], $null, 'DoNotExpandEnvironmentNames')
        switch ($Action['type']) {
            'MultiString' { return ((@($current) -join "`n") -ceq (@($Action['value']) -join "`n")) }
            { $_ -in 'DWord', 'QWord' } {
                return (ConvertTo-OSSetupRegistryNumber -Value $current -Type $_ -Unsigned) -eq
                (ConvertTo-OSSetupRegistryNumber -Value $Action['value'] -Type $_ -Unsigned)
            }
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
        # Une valeur existante d'un autre type est remplacée (-Force). DWord et QWord sont écrits sous leur forme signée,
        # la seule qu'accepte le registre de PowerShell (0xFFFFFFFF : -1).
        $value = $Action['value']
        if ($Action['type'] -in 'DWord', 'QWord') { $value = ConvertTo-OSSetupRegistryNumber -Value $value -Type $Action['type'] }
        New-ItemProperty -Path $Action['path'] -Name $Action['name'] -PropertyType $Action['type'] -Value $value -Force | Out-Null
    }
}
