function Test-OSSetupElevated {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not $IsWindows) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-OSSetupInteractiveUser {
    <#
    .SYNOPSIS
        Vérifie que le compte qui exécute le setup est celui de la session ouverte (propriétaire d'explorer.exe).
    .DESCRIPTION
        Depuis un compte standard, l'élévation se fait avec les identifiants d'un autre compte administrateur :
        les réglages « utilisateur » (HKCU, profil, installations par utilisateur) iraient alors dans le profil
        de cet administrateur. Le setup s'arrête dans ce cas.
    #>
    [CmdletBinding()]
    param()
    if (-not $IsWindows) { return }
    if (-not (Test-OSSetupElevated)) { return }  # -IncludeUserName exige les droits administrateur
    $sessionId = (Get-Process -Id $PID).SessionId
    $explorer = Get-Process -Name 'explorer' -IncludeUserName -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sessionId -and $_.UserName } |
        Select-Object -First 1
    if (-not $explorer) {
        Write-OSSetupLog -Level Warning -Message "Utilisateur de la session introuvable (explorer.exe absent) : vérification ignorée."
        return
    }
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($explorer.UserName -ne $current) {
        throw ("La session est ouverte par « {0} » mais le setup s'exécute en tant que « {1} ». " +
            'Les réglages utilisateur seraient appliqués au mauvais profil. ' +
            'Lancez le setup depuis un compte administrateur (ou ajoutez temporairement ce compte au groupe Administrateurs).') -f
            $explorer.UserName, $current
    }
}

function ConvertTo-OSSetupCommandArgument {
    <#
    .SYNOPSIS
        Convertit des paramètres liés ($PSBoundParameters) en texte d'appel PowerShell (-Nom 'valeur').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Parameter
    )
    $quote = { param($Value) "'" + ("$Value" -replace "'", "''") + "'" }
    $parts = foreach ($name in $Parameter.Keys) {
        $value = $Parameter[$name]
        if ($value -is [switch] -or $value -is [bool]) {
            if ($value) { "-$name" }
        }
        elseif ($value -is [array]) {
            "-$name " + (($value | ForEach-Object { & $quote $_ }) -join ',')
        }
        else {
            "-$name " + (& $quote $value)
        }
    }
    $parts -join ' '
}
