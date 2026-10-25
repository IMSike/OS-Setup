$script:LogPath = $null

function Start-OSSetupLog {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Le journal est toujours écrit, y compris en -WhatIf.')]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$RunId
    )
    # Le journal est toujours écrit, y compris en -WhatIf.
    New-Item -Path $Directory -ItemType Directory -Force -WhatIf:$false | Out-Null
    $script:LogPath = Join-Path -Path $Directory -ChildPath "setup-$RunId.log"
    $script:LogPath
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
        Add-Content -Path $script:LogPath -Value $line -Encoding utf8 -WhatIf:$false
    }
}
