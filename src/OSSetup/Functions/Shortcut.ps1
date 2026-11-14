# Fonctions d'appui du provider shortcut.

function Get-OSSetupShortcutTarget {
    <#
    .SYNOPSIS
        Cible d'un raccourci .lnk (lecture seule : le raccourci n'est pas réenregistré).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    $shell = New-Object -ComObject WScript.Shell
    try {
        "$($shell.CreateShortcut($Path).TargetPath)"
    }
    finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}
