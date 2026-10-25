function Get-OSSetupPathEntry {
    <#
    .SYNOPSIS
        Retourne les entrées d'une variable PATH (portée User ou Machine, lue dans le registre), sans doublon ni vide.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Machine')]
        [string]$Scope
    )
    $value = [Environment]::GetEnvironmentVariable('Path', $Scope)
    ConvertTo-OSSetupPathList -Value $value
}

function ConvertTo-OSSetupPathList {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Value
    )
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in "$Value" -split [System.IO.Path]::PathSeparator) {
        $trimmed = $entry.Trim()
        if ($trimmed -and $seen.Add($trimmed.TrimEnd('\'))) { $trimmed }
    }
}

function Add-OSSetupPathEntry {
    <#
    .SYNOPSIS
        Ajoute un dossier au PATH persistant (registre), sans développer les %VARIABLES% existantes,
        puis notifie Windows et recharge le PATH de la session.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('User', 'Machine')]
        [string]$Scope
    )
    $keyPath = if ($Scope -eq 'Machine') { 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' } else { 'HKCU:\Environment' }
    $key = Get-Item -Path $keyPath
    $raw = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $entries = @(ConvertTo-OSSetupPathList -Value $raw)
    if ($entries | Where-Object { $_.TrimEnd('\') -eq $Path.TrimEnd('\') }) { return }

    if ($PSCmdlet.ShouldProcess("PATH ($Scope)", "Ajouter $Path")) {
        $newValue = (@($entries) + $Path) -join [System.IO.Path]::PathSeparator
        Set-ItemProperty -Path $keyPath -Name 'Path' -Value $newValue -Type ExpandString
        Send-OSSetupEnvironmentChange
        Update-OSSetupSessionPath
    }
}

function Send-OSSetupEnvironmentChange {
    <#
    .SYNOPSIS
        Diffuse WM_SETTINGCHANGE pour que l'Explorateur (et les programmes lancés ensuite) voient les nouvelles variables.
    #>
    [CmdletBinding()]
    param()
    if (-not ('OSSetup.NativeMethods' -as [type])) {
        Add-Type -Namespace OSSetup -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    # HWND_BROADCAST = 0xFFFF, WM_SETTINGCHANGE = 0x1A, SMTO_ABORTIFHUNG = 0x2
    [void][OSSetup.NativeMethods]::SendMessageTimeout([IntPtr]0xFFFF, 0x1A, [UIntPtr]::Zero, 'Environment', 0x2, 5000, [ref]$result)
}

function Update-OSSetupSessionPath {
    <#
    .SYNOPSIS
        Recharge le PATH de la session depuis le registre (Machine puis User) après une installation,
        en conservant les entrées propres à la session.
    .DESCRIPTION
        Les installeurs modifient le PATH dans le registre, mais les processus déjà lancés gardent l'ancienne valeur.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Ne modifie que le PATH du processus courant, nécessaire aussi en -WhatIf.')]
    param()
    $entries = @(Get-OSSetupPathEntry -Scope Machine) + @(Get-OSSetupPathEntry -Scope User) +
        @(ConvertTo-OSSetupPathList -Value $env:Path)
    $env:Path = (ConvertTo-OSSetupPathList -Value ($entries -join [System.IO.Path]::PathSeparator)) -join [System.IO.Path]::PathSeparator
}
