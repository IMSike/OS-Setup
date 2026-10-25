<#
.SYNOPSIS
    Exécuté DANS la VM par une tâche planifiée (session de l'utilisateur de test, droits élevés) :
    lance bootstrap.ps1 comme le ferait un utilisateur, journalise la console et écrit le code de sortie.
    Doit rester compatible Windows PowerShell 5.1 (machine vierge).
#>
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$SetupArguments
)

$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$logRoot = Join-Path -Path $repoRoot -ChildPath 'logs'
New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
$exitFile = Join-Path -Path $logRoot -ChildPath 'guest-exitcode.txt'
Remove-Item -Path $exitFile -ErrorAction SilentlyContinue

Set-Location -Path $repoRoot
Start-Transcript -Path (Join-Path -Path $logRoot -ChildPath 'guest-transcript.log') -Force | Out-Null
$code = 1
try {
    & (Join-Path -Path $repoRoot -ChildPath 'bootstrap.ps1') -NoPause @SetupArguments
    $code = $LASTEXITCODE
}
catch {
    Write-Host -Object "ERREUR : $($_.Exception.Message)"
}
finally {
    Stop-Transcript | Out-Null
    Set-Content -Path $exitFile -Value $code
}
