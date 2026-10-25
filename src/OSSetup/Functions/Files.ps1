function Get-OSSetupFileContent {
    <#
    .SYNOPSIS
        Retourne le contenu attendu (octets) d'un fichier déployé. En mode template, les {{Variables}}
        sont remplacées et le BOM UTF-8 éventuel de la source est conservé.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Le tableau d''octets est émis d''un bloc (virgule unaire) : le type réel est bien [byte[]].')]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Action,

        [Parameter(Mandatory)]
        [hashtable]$Context
    )
    $sourcePath = Join-Path -Path $Context.DotfilesRoot -ChildPath $Action['source']
    if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
        throw "Source introuvable : $sourcePath"
    }
    $bytes = [System.IO.File]::ReadAllBytes($sourcePath)
    if ($Action['mode'] -eq 'merge-json') {
        # Fusion : le dépôt ne fournit que les clés gérées ; celles déjà présentes dans la cible sont conservées.
        $managed = ConvertFrom-OSSetupJsonText -Text ([System.Text.Encoding]::UTF8.GetString($bytes)) -Name $sourcePath
        $current = if (Test-Path -Path $Action['target'] -PathType Leaf) {
            ConvertFrom-OSSetupJsonText -Text (Get-Content -Path $Action['target'] -Raw -Encoding utf8) -Name $Action['target']
        }
        else { [ordered]@{} }
        $merged = Merge-OSSetupJson -Target $current -Source $managed
        return , [System.Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $merged -Depth 32) + "`n")
    }
    if ($Action['mode'] -ne 'template') {
        return , $bytes
    }

    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $encoding = [System.Text.UTF8Encoding]::new($hasBom)
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    $expanded = Expand-OSSetupString -Text $text -Variables $Context.Variables
    , [byte[]]($encoding.GetPreamble() + $encoding.GetBytes($expanded))
}

function ConvertFrom-OSSetupJsonText {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary], [hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Name
    )
    if (-not $Text.Trim()) { return [ordered]@{} }
    try {
        $Text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        throw "JSON illisible ($Name) : $($_.Exception.Message)"
    }
}

function Merge-OSSetupJson {
    <#
    .SYNOPSIS
        Fusion profonde : les clés de Source remplacent celles de Target ; les objets sont fusionnés récursivement,
        les autres valeurs (tableaux compris) remplacées. Retourne un nouvel objet.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]$Target,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]$Source
    )
    $result = [ordered]@{}
    foreach ($key in $Target.Keys) { $result[$key] = $Target[$key] }
    foreach ($key in $Source.Keys) {
        if ($Source[$key] -is [System.Collections.IDictionary] -and $result[$key] -is [System.Collections.IDictionary]) {
            $result[$key] = Merge-OSSetupJson -Target $result[$key] -Source $Source[$key]
        }
        else {
            $result[$key] = $Source[$key]
        }
    }
    $result
}

function Test-OSSetupJsonSubset {
    <#
    .SYNOPSIS
        Vrai si toutes les clés de Subset sont présentes dans Json avec la même valeur (objets comparés récursivement).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]$Json,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary]$Subset
    )
    foreach ($key in $Subset.Keys) {
        if (-not $Json.Contains($key)) { return $false }
        if ($Subset[$key] -is [System.Collections.IDictionary]) {
            if ($Json[$key] -isnot [System.Collections.IDictionary]) { return $false }
            if (-not (Test-OSSetupJsonSubset -Json $Json[$key] -Subset $Subset[$key])) { return $false }
        }
        elseif ((ConvertTo-Json -InputObject $Json[$key] -Depth 32 -Compress) -cne (ConvertTo-Json -InputObject $Subset[$key] -Depth 32 -Compress)) {
            return $false
        }
    }
    $true
}

function Backup-OSSetupFile {
    <#
    .SYNOPSIS
        Copie un fichier dans le dossier de sauvegarde de l'exécution, en reproduisant son chemin. Retourne la copie.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$BackupRoot
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $relative = $fullPath -replace '^([A-Za-z]):', '$1' -replace '^[\\/]+', ''
    $destination = Join-Path -Path $BackupRoot -ChildPath $relative
    if ($PSCmdlet.ShouldProcess($fullPath, "Sauvegarder vers $destination")) {
        New-Item -Path (Split-Path -Path $destination -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item -Path $fullPath -Destination $destination -Force
    }
    $destination
}
