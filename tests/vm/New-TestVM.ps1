#Requires -Version 7.4
<#
.SYNOPSIS
    Crée une VM Hyper-V Windows vierge pour tester OS-Setup, sans ISO ni clic.
.DESCRIPTION
    1. Copie l'image Windows (install.esd / install.wim, ex. depuis une clé USB, ou extraite d'une ISO) dans un
       cache hors dépôt, propre à la VM.
    2. Crée un disque virtuel, y applique l'édition demandée (DISM) et le rend démarrable (bcdboot).
    3. Dépose unattend.xml : écrans de première configuration passés, compte « tester », connexion automatique.
    4. Crée la VM (génération 2, démarrage sécurisé et TPM virtuel, comme une machine Windows 11), attend la fin
       de l'installation, l'arrête et pose le point de contrôle « vierge ».
    À lancer en administrateur.
.EXAMPLE
    ./tests/vm/New-TestVM.ps1 -ImagePath D:\sources\install.esd
.EXAMPLE
    ./tests/vm/New-TestVM.ps1 -Name OSSetup-Win11 -ImagePath C:\ProgramData\OSSetup-Tests\iso\Win11.iso
#>
[CmdletBinding()]
param(
    [string]$Name = 'OSSetup-Win10',

    # install.esd, install.wim ou ISO d'installation. Copié dans le cache au premier usage, ensuite inutile.
    [string]$ImagePath = 'D:\sources\install.esd',

    # Champ « Edition » de DISM (Professional = Windows 10 ou 11 Pro).
    [string]$Edition = 'Professional',

    [int]$MemoryGB = 8,

    [int]$ProcessorCount = 4,

    [int]$DiskGB = 100,

    # Supprime et recrée la VM si elle existe déjà.
    [switch]$Force
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'TestVM.Common.ps1')
Assert-TestVMAdministrator

$root = Get-TestVMRoot
$imageCache = Join-Path -Path $root -ChildPath 'images'
$vmRoot = Join-Path -Path $root -ChildPath 'vms'
$vhdPath = Join-Path -Path $vmRoot -ChildPath "$Name\$Name.vhdx"
New-Item -Path $imageCache, $vmRoot -ItemType Directory -Force | Out-Null

if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
    if (-not $Force) { throw "La VM '$Name' existe déjà (utiliser -Force pour la recréer)." }
    Write-TestVMStep "Suppression de la VM existante '$Name'"
    Stop-VM -Name $Name -TurnOff -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $Name -Force
    Remove-Item -Path (Split-Path -Path $vhdPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Image -------------------------------------------------------------------------------------
# Un cache par VM : les images Windows 10 et 11 portent le même nom de fichier.
$cachedImage = @(Get-ChildItem -Path (Join-Path -Path $imageCache -ChildPath $Name) -Include 'install.esd', 'install.wim' -Recurse -ErrorAction SilentlyContinue) |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $cachedImage) {
    if (-not (Test-Path -Path $ImagePath)) { throw "Image introuvable : $ImagePath" }
    New-Item -Path (Join-Path -Path $imageCache -ChildPath $Name) -ItemType Directory -Force | Out-Null
    $iso = $null
    $source = $ImagePath
    if ([IO.Path]::GetExtension($ImagePath) -eq '.iso') {
        $iso = Mount-DiskImage -ImagePath (Resolve-Path -Path $ImagePath).Path -PassThru
        $letter = ($iso | Get-Volume).DriveLetter
        $source = @(Get-ChildItem -Path "${letter}:\sources\install.wim", "${letter}:\sources\install.esd" -ErrorAction SilentlyContinue) |
            Select-Object -First 1 -ExpandProperty FullName
    }
    try {
        if (-not $source) { throw "Aucun install.wim ni install.esd dans $ImagePath." }
        $cachedImage = Join-Path -Path $imageCache -ChildPath "$Name\$(Split-Path -Path $source -Leaf)"
        Write-TestVMStep "Copie de l'image dans le cache ($cachedImage)"
        Copy-Item -Path $source -Destination $cachedImage
    }
    finally {
        if ($iso) { Dismount-DiskImage -ImagePath $iso.ImagePath | Out-Null }
    }
}

Write-TestVMStep "Recherche de l'édition '$Edition'"
$summary = & dism.exe /English /Get-WimInfo "/WimFile:$cachedImage"
if ($LASTEXITCODE -ne 0) { throw "DISM n'a pas pu lire l'image : $($summary -join ' ')" }
$indexes = $summary | Select-String -Pattern '^Index : (\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value }
$image = $null
foreach ($index in $indexes) {
    $details = & dism.exe /English /Get-WimInfo "/WimFile:$cachedImage" "/Index:$index"
    $editionLine = $details | Select-String -Pattern '^Edition : (.+)$' | Select-Object -First 1
    if ($editionLine -and $editionLine.Matches[0].Groups[1].Value.Trim() -eq $Edition) {
        $languageLine = $details | Select-String -Pattern '^\s+([a-z]{2}-[A-Z]{2}) \(Default\)' | Select-Object -First 1
        $image = [pscustomobject]@{
            Index    = $index
            Name     = ($details | Select-String -Pattern '^Name : (.+)$').Matches[0].Groups[1].Value.Trim()
            Language = if ($languageLine) { $languageLine.Matches[0].Groups[1].Value } else { 'en-US' }
        }
        break
    }
}
if (-not $image) { throw "Édition '$Edition' absente de l'image (index disponibles : $($indexes -join ', '))." }
Write-TestVMStep "Image retenue : index $($image.Index), $($image.Name), langue $($image.Language)"

# --- Disque virtuel ----------------------------------------------------------------------------
Write-TestVMStep "Création du disque virtuel ($DiskGB Go, dynamique)"
New-Item -Path (Split-Path -Path $vhdPath -Parent) -ItemType Directory -Force | Out-Null
New-VHD -Path $vhdPath -SizeBytes ($DiskGB * 1GB) -Dynamic | Out-Null
$disk = Mount-VHD -Path $vhdPath -Passthru | Get-Disk
try {
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT
    # Partitions UEFI standard : système EFI, réservée Microsoft (MSR), Windows.
    $efi = New-Partition -DiskNumber $disk.Number -Size 260MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'System' -Confirm:$false | Out-Null
    New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null
    $windows = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
    Format-Volume -Partition $windows -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false | Out-Null

    $efi | Add-PartitionAccessPath -AssignDriveLetter
    $windows | Add-PartitionAccessPath -AssignDriveLetter
    $efiLetter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $efi.PartitionNumber).DriveLetter
    $windowsLetter = (Get-Partition -DiskNumber $disk.Number -PartitionNumber $windows.PartitionNumber).DriveLetter

    Write-TestVMStep "Application de l'image sur ${windowsLetter}: (quelques minutes)"
    & dism.exe /English /Apply-Image "/ImageFile:$cachedImage" "/Index:$($image.Index)" "/ApplyDir:${windowsLetter}:\"
    if ($LASTEXITCODE -ne 0) { throw "Échec de l'application de l'image (code $LASTEXITCODE)." }

    Write-TestVMStep 'Configuration du démarrage UEFI'
    & bcdboot.exe "${windowsLetter}:\Windows" /s "${efiLetter}:" /f UEFI
    if ($LASTEXITCODE -ne 0) { throw "Échec de bcdboot (code $LASTEXITCODE)." }

    Write-TestVMStep 'Dépôt du fichier de réponses'
    $inputLocales = @{ 'fr-FR' = '040c:0000040c'; 'en-US' = '0409:00000409' }
    $adminGroups = @{ 'fr' = 'Administrateurs'; 'de' = 'Administratoren'; 'es' = 'Administradores' }
    # Nom NetBIOS : 15 caractères maximum, lettres, chiffres et tirets.
    $computerName = $Name.ToUpperInvariant() -replace '[^A-Z0-9-]', ''
    $values = @{
        ComputerName = $computerName.Substring(0, [Math]::Min(15, $computerName.Length))
        Language     = $image.Language
        InputLocale  = if ($inputLocales.ContainsKey($image.Language)) { $inputLocales[$image.Language] } else { $image.Language }
        AdminGroup   = if ($adminGroups.ContainsKey($image.Language.Substring(0, 2))) { $adminGroups[$image.Language.Substring(0, 2)] } else { 'Administrators' }
        UserName     = $script:TestUserName
        Password     = $script:TestPassword
    }
    $unattend = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'unattend.xml') -Raw -Encoding utf8
    foreach ($key in $values.Keys) { $unattend = $unattend.Replace("{{$key}}", $values[$key]) }
    $panther = "${windowsLetter}:\Windows\Panther"
    New-Item -Path $panther -ItemType Directory -Force | Out-Null
    Set-Content -Path (Join-Path -Path $panther -ChildPath 'unattend.xml') -Value $unattend -Encoding utf8
}
finally {
    Dismount-VHD -Path $vhdPath
}

# --- VM ----------------------------------------------------------------------------------------
Write-TestVMStep "Création de la VM '$Name'"
$switch = Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue
$vm = New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryGB * 1GB) -VHDPath $vhdPath -Path $vmRoot
Set-VMMemory -VM $vm -DynamicMemoryEnabled $false
Set-VMProcessor -VM $vm -Count $ProcessorCount
Set-VM -VM $vm -AutomaticCheckpointsEnabled $false -CheckpointType Standard
# TPM virtuel (protecteur de clé local) : prérequis de Windows 11, sans effet gênant pour Windows 10.
Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
Enable-VMTPM -VM $vm
if ($switch) { Connect-VMNetworkAdapter -VMName $Name -SwitchName $switch.Name }
else { Write-Warning "Commutateur « Default Switch » introuvable : la VM n'aura pas de réseau." }
# Service d'invité : nécessaire pour copier des fichiers vers la VM (identifiant indépendant de la langue).
Get-VMIntegrationService -VM $vm | Where-Object { $_.Id -match '6C09BB55-D683-4DA0-8931-C9BF705F6480' } | Enable-VMIntegrationService

Write-TestVMStep 'Démarrage : installation de Windows et première ouverture de session (10 à 20 minutes)'
Start-VM -VM $vm
Wait-TestVMReady -Name $Name -TimeoutMinutes 40

Write-TestVMStep 'Arrêt de la VM et point de contrôle « vierge »'
Stop-VM -VM $vm -Force
Checkpoint-VM -VM $vm -SnapshotName $script:BaselineCheckpoint
Write-TestVMStep "VM '$Name' prête. Tests : ./tests/vm/Invoke-TestVM.ps1 ; retour à l'état vierge : ./tests/vm/Reset-TestVM.ps1"
