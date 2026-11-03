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

function Clear-OSSetupWingetExportCache {
    <#
    .SYNOPSIS
        Oublie l'export winget lu : le prochain appel de Get-OSSetupWingetExportId le relit (après une désinstallation).
    #>
    [CmdletBinding()]
    param()
    Remove-Variable -Name WingetExportId -Scope Script -ErrorAction SilentlyContinue
}

function Get-OSSetupWingetSource {
    <#
    .SYNOPSIS
        Source winget d'une action du provider winget (winget par défaut).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action
    )
    if ($Action['source']) { $Action['source'] } else { 'winget' }
}

function Test-OSSetupWingetInstalled {
    <#
    .SYNOPSIS
        Vrai si le paquet winget est installé : `winget list --id`, puis `winget export` en second avis.
    .DESCRIPTION
        L'export ne couvre que la source winget : il n'est pas consulté pour un paquet d'une autre source (msstore),
        ni avec -ListOnly (sondage léger pendant l'attente qui suit une installation).
        Avec -ExportFirst (plan), l'export, lu une seule fois pour la passe, est consulté avant `winget list`
        (0,6 à 2 s par paquet) : un paquet qu'il contient est installé sans autre appel. Le résultat est le même,
        seul l'ordre change ; pendant l'exécution, `winget list` reste le premier avis (état le plus frais).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        # Source winget du paquet (winget par défaut).
        [string]$Source = 'winget',

        # Relit l'export (après une installation).
        [switch]$Refresh,

        # winget list seul, sans second avis.
        [switch]$ListOnly,

        # Export consulté d'abord (plan).
        [switch]$ExportFirst
    )
    $useExport = -not $ListOnly -and $Source -eq 'winget'
    if ($ExportFirst -and $useExport -and $Id -in @(Get-OSSetupWingetExportId -Refresh:$Refresh)) { return $true }
    & winget list --id $Id --exact --accept-source-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -eq 0) { return $true }
    # Avec -ExportFirst, l'export vient d'être consulté.
    if (-not $useExport -or $ExportFirst) { return $false }
    $Id -in @(Get-OSSetupWingetExportId -Refresh:$Refresh)
}
