function Get-OSSetupWingetExportId {
    <#
    .SYNOPSIS
        Identifiants winget des paquets installés selon `winget export`, gardés en cache pour la passe (-Refresh relit).
    .DESCRIPTION
        `winget list --id` ne retrouve pas toujours un paquet installé que winget sait pourtant rattacher à son
        identifiant (ex. PowerShell 7 mis à jour par Microsoft Update : 7.6.8, MSI). `winget export` fait ce
        rattachement : il sert de second avis, lu une seule fois tant que rien n'est installé.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [switch]$Refresh
    )
    if ($Refresh -or -not (Get-Variable -Name WingetExportId -Scope Script -ErrorAction SilentlyContinue)) {
        $file = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath "os-setup-winget-$PID.json"
        try {
            & winget export --output $file --source winget --accept-source-agreements --disable-interactivity *> $null
            $script:WingetExportId = @(
                if ($LASTEXITCODE -eq 0 -and (Test-Path -Path $file)) {
                    (Get-Content -Path $file -Raw | ConvertFrom-Json).Sources | ForEach-Object { $_.Packages.PackageIdentifier }
                }
            )
        }
        finally {
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
        }
    }
    $script:WingetExportId
}

function Test-OSSetupWingetInstalled {
    <#
    .SYNOPSIS
        Vrai si le paquet winget est installé : `winget list --id`, puis `winget export` en second avis.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        # Relit l'export (après une installation).
        [switch]$Refresh
    )
    & winget list --id $Id --exact --accept-source-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    $Id -in @(Get-OSSetupWingetExportId -Refresh:$Refresh)
}
