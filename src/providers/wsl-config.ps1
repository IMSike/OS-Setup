# Provider wsl-config : une clé de %USERPROFILE%\.wslconfig (réglages de la VM WSL 2, donc aussi de Docker Desktop).
# Clé par clé : le reste du fichier est conservé. memoryPercent calcule le plafond mémoire selon la RAM de la machine.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'wsl-config'

    Describe = {
        param($Action, $Context)
        $value = Get-OSSetupWslConfigValue -Action $Action
        if ($null -eq $value) { return "WSL : $($Action['key']) laissé par défaut (mémoire de la machine trop faible)" }
        if ($Action.Contains('memoryPercent')) { return "WSL : $($Action['key']) = $value ($($Action['memoryPercent']) % de la RAM)" }
        "WSL : $($Action['key']) = $value"
    }

    Test     = {
        param($Action, $Context)
        $value = Get-OSSetupWslConfigValue -Action $Action
        if ($null -eq $value) { return $true }
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.wslconfig'
        if (-not (Test-Path -Path $path -PathType Leaf)) { return $false }
        $current = Get-OSSetupIniValue -Text (Get-Content -Path $path -Raw -Encoding utf8) -Section $Action['section'] -Key $Action['key']
        $current -eq $value
    }

    Read     = {
        param($Action, $Context)
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.wslconfig'
        $current = if (Test-Path -Path $path -PathType Leaf) {
            Get-OSSetupIniValue -Text (Get-Content -Path $path -Raw -Encoding utf8) -Section $Action['section'] -Key $Action['key']
        }
        if ($null -ne $current) { [ordered]@{ exists = $true; value = $current } } else { [ordered]@{ exists = $false } }
    }

    Invoke   = {
        param($Action, $Context)
        $value = Get-OSSetupWslConfigValue -Action $Action -Log
        if ($null -eq $value) { return }
        $path = Join-Path -Path $env:USERPROFILE -ChildPath '.wslconfig'
        $text = ''
        if (Test-Path -Path $path -PathType Leaf) {
            $backup = Backup-OSSetupFile -Path $path -BackupRoot $Context.BackupRoot
            Write-OSSetupLog -Level Detail -Message "  sauvegarde : $backup"
            $text = Get-Content -Path $path -Raw -Encoding utf8
        }
        $updated = Set-OSSetupIniValue -Text $text -Section $Action['section'] -Key $Action['key'] -Value $value
        [System.IO.File]::WriteAllText($path, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-OSSetupLog -Level Detail -Message '  pris en compte au prochain démarrage de WSL (wsl --shutdown pour l''appliquer tout de suite)'
    }
}
