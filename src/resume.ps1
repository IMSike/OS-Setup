<#
.SYNOPSIS
    Lanceur de la reprise du setup après redémarrage, exécuté par la tâche « OS-Setup - reprise » (Windows PowerShell
    5.1, droits les plus élevés, à l'ouverture de session).
.DESCRIPTION
    Copié à la racine de la copie figée du setup (%ProgramFiles%\OS-Setup\resume, modifiable par les seuls
    administrateurs), à côté de setup.ps1 et de state\run.json : rien de ce que la tâche exécute ou lit ne peut être
    modifié par un programme lancé sous le compte de l'utilisateur (ADR 0005).
    Il lance setup.ps1 -Resume avec le pwsh.exe du dossier du paquet du PowerShell 7 du Store, retrouvé à chaque
    reprise par l'API des paquets (le chemin contient la version, qui change à chaque mise à jour), à défaut celui du
    MSI de PowerShell 7 sous Program Files ; jamais l'alias d'exécution du profil, que l'utilisateur peut remplacer.
    Uniquement du .NET : aucun module n'est chargé, donc aucun module déposé dans le profil de l'utilisateur.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ResumePwshPath {
    <#
    .SYNOPSIS
        pwsh.exe de la version la plus récente du PowerShell 7 du Store installée pour le compte, sinon celui du MSI
        de PowerShell 7, sinon $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $found = $null
    $foundVersion = $null
    try {
        $null = [Windows.Management.Deployment.PackageManager, Windows.Management.Deployment, ContentType = WindowsRuntime]
        $manager = [Windows.Management.Deployment.PackageManager]::new()
        foreach ($package in $manager.FindPackagesForUser('', 'Microsoft.PowerShell_8wekyb3d8bbwe')) {
            $id = $package.Id.Version
            $version = [version]::new($id.Major, $id.Minor, $id.Build, $id.Revision)
            $exe = [IO.Path]::Combine($package.InstalledLocation.Path, 'pwsh.exe')
            if ([IO.File]::Exists($exe) -and ($null -eq $foundVersion -or $version -gt $foundVersion)) {
                $found = $exe
                $foundVersion = $version
            }
        }
    }
    catch {
        [Console]::Error.WriteLine("Paquets du Store illisibles : $($_.Exception.Message)")
    }
    if ($found) { return $found }
    $msi = [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'PowerShell\7\pwsh.exe')
    if ([IO.File]::Exists($msi)) { return $msi }
    $null
}

$setup = [IO.Path]::Combine($PSScriptRoot, 'setup.ps1')
$pwsh = Get-ResumePwshPath
if (-not $pwsh) {
    [Console]::Error.WriteLine('PowerShell 7 introuvable : reprise du setup impossible. Relancer setup.ps1 à la main.')
    exit 1
}
$start = [Diagnostics.ProcessStartInfo]::new($pwsh, ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Resume' -f $setup))
# Même console que le lanceur (fenêtre de la reprise) ; dossier courant hors de la copie, que le setup supprime à la fin.
$start.UseShellExecute = $false
$start.WorkingDirectory = [IO.Path]::GetDirectoryName($PSScriptRoot)
$process = [Diagnostics.Process]::Start($start)
$process.WaitForExit()
exit $process.ExitCode
