<#
.SYNOPSIS
    Lanceur de la reprise du setup après redémarrage, exécuté par la tâche « OS-Setup - reprise » (Windows PowerShell
    5.1, droits les plus élevés, à l'ouverture de session).
.DESCRIPTION
    Copié à la racine de la copie figée du setup (%ProgramFiles%\OS-Setup\resume, modifiable par les seuls
    administrateurs), à côté de setup.ps1 et de state\run.json : rien de ce que la tâche exécute ou lit ne peut être
    modifié par un programme lancé sous le compte de l'utilisateur (ADR 0005).
    Il lance setup.ps1 -Resume avec le pwsh.exe du MSI de PowerShell 7 sous Program Files, modifiable par les seuls
    administrateurs ; jamais un pwsh trouvé par le PATH ou un alias du profil, que l'utilisateur peut remplacer.
    Uniquement du .NET : aucun module n'est chargé, donc aucun module déposé dans le profil de l'utilisateur.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$setup = [IO.Path]::Combine($PSScriptRoot, 'setup.ps1')
$pwsh = [IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'PowerShell\7\pwsh.exe')
if (-not [IO.File]::Exists($pwsh)) {
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
