# Provider directory : création d'un dossier.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface commune des providers : chaque bloc reçoit $Action et $Context, utilisés ou non.')]
param()

@{
    Name     = 'directory'

    Describe = {
        param($Action, $Context)
        "créer le dossier $($Action['path'])"
    }

    Test     = {
        param($Action, $Context)
        Test-Path -Path $Action['path'] -PathType Container
    }

    Invoke   = {
        param($Action, $Context)
        New-Item -Path $Action['path'] -ItemType Directory -Force | Out-Null
    }
}
