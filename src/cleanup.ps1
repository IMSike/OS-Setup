<#
.SYNOPSIS
    Nettoyage de fin de setup, exécuté après la fermeture du setup (Windows PowerShell 5.1, processus détaché).
.DESCRIPTION
    Copié dans %TEMP% puis lancé par le setup : un script ne peut pas supprimer son propre dossier pendant
    qu'il s'exécute, et PowerShell 7 ne peut pas être désinstallé tant qu'il est en cours d'utilisation.
    Lit sa configuration (JSON) : processus à attendre, paquets winget à désinstaller, chemins à supprimer,
    journal où consigner le résultat, fermeture de session. Supprime ensuite sa configuration et lui-même, puis ferme la session si demandé.
#>
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Continue'
$config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Write-CleanupLog {
    param([string]$Message)
    if ($config.logPath) {
        $line = '{0:yyyy-MM-dd HH:mm:ss} [CLEANUP] {1}' -f (Get-Date), $Message
        Add-Content -Path $config.logPath -Value $line -Encoding UTF8
    }
}

# Attend la fin du setup (fenêtre fermée).
Wait-Process -Id $config.waitPid -ErrorAction SilentlyContinue

foreach ($id in @($config.uninstall | Where-Object { $_ })) {
    & winget uninstall --id $id --exact --silent --disable-interactivity --accept-source-agreements | Out-Null
    Write-CleanupLog ('Désinstallation de {0} : code {1}' -f $id, $LASTEXITCODE)
}

foreach ($path in @($config.remove | Where-Object { $_ })) {
    # Quelques essais : un fichier peut rester verrouillé un court instant après la fermeture du setup.
    $removed = $false
    for ($attempt = 1; $attempt -le 15 -and -not $removed; $attempt++) {
        try {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
            $removed = $true
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    Write-CleanupLog ('Suppression de {0} : {1}' -f $path, $(if ($removed) { 'faite' } else { 'impossible' }))
}

Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue

# En dernier : fermer la session interromprait le nettoyage.
if ($config.PSObject.Properties['logoff'] -and $config.logoff) {
    Write-CleanupLog 'Fermeture de la session'
    & shutdown.exe /l
}
