$script:LogPath = $null

function Start-OSSetupLog {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Le journal est toujours écrit, y compris en -WhatIf.')]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$RunId
    )
    # Le journal est toujours écrit, y compris en -WhatIf.
    $path = Join-Path -Path $Directory -ChildPath "setup-$RunId.log"
    Assert-OSSetupDataPath -Path $path
    New-Item -Path $Directory -ItemType Directory -Force -WhatIf:$false | Out-Null
    $script:LogPath = $path
    $path
}

function Write-OSSetupLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Detail')]
        [string]$Level = 'Info'
    )
    $colors = @{ Info = 'Gray'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red'; Detail = 'DarkGray' }
    Write-Host -Object $Message -ForegroundColor $colors[$Level]
    if ($script:LogPath) {
        $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level.ToUpperInvariant(), $Message
        try {
            Assert-OSSetupDataPath -Path $script:LogPath
            Add-Content -LiteralPath $script:LogPath -Value $line -Encoding utf8 -WhatIf:$false
        }
        catch {
            # Journal arrêté (la suite s'affiche seulement), puis échec de l'opération en cours : le message d'erreur qui
            # suit (bloc catch de l'appelant) s'affiche au lieu de lever à son tour.
            $script:LogPath = $null
            Write-Host -Object "Journal arrêté : $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }
}
