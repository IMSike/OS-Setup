function Invoke-OSSetupNativeCommand {
    <#
    .SYNOPSIS
        Lance une commande externe : sortie (standard et erreurs) journalisée ligne à ligne en Detail, exception si le
        code de sortie n'est pas 0 (« <Label> a échoué (code N). »).
    .PARAMETER Utf8
        L'outil écrit en UTF-8 : la console passe en UTF-8 le temps de l'appel (sinon PowerShell décode la sortie avec
        la page de code OEM et les accents sont corrompus dans le journal).
    .PARAMETER LogFilter
        Expression régulière : les lignes qui y correspondent ne sont pas journalisées (ex. barres de progression).
    .PARAMETER NoInput
        Entrée standard vide : aucune question de l'outil ne peut bloquer le setup.
    .PARAMETER NoThrow
        Pas d'exception en cas d'échec ; avec -PassThru, l'appelant lit le code de sortie.
    .PARAMETER PassThru
        Retourne la sortie et le code de sortie ({ Output; ExitCode }).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$Label,

        [switch]$Utf8,

        [string]$LogFilter,

        [switch]$NoInput,

        [switch]$NoThrow,

        [switch]$PassThru
    )
    $previousEncoding = [Console]::OutputEncoding
    try {
        if ($Utf8) { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
        $output = if ($NoInput) { $null | & $FilePath @ArgumentList 2>&1 } else { & $FilePath @ArgumentList 2>&1 }
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($Utf8) { [Console]::OutputEncoding = $previousEncoding }
    }
    foreach ($line in $output) {
        if ("$line".Trim() -and -not ($LogFilter -and "$line" -match $LogFilter)) { Write-OSSetupLog -Level Detail -Message "  $line" }
    }
    if ($exitCode -ne 0 -and -not $NoThrow) {
        if (-not $Label) { $Label = (@($FilePath) + @($ArgumentList | Select-Object -First 1)) -join ' ' }
        throw "$Label a échoué (code $exitCode)."
    }
    if ($PassThru) { [pscustomobject]@{ Output = @($output); ExitCode = $exitCode } }
}
