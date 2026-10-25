<#
.SYNOPSIS
    Capture l'écran de la VM de test dans un fichier PNG, après avoir éventuellement lancé une commande dans la
    session de l'utilisateur (ex. une page de Paramètres) : vérification visuelle d'un réglage.
.EXAMPLE
    ./tests/vm/Get-TestVMScreenshot.ps1 -Path logs\vm\camera.png -Open 'ms-settings:privacy-webcam'
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '', Justification = 'Faux positif avec Invoke-Command -Session : les valeurs passent par -ArgumentList et le bloc param.')]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$Name = 'OSSetup-Win10',

    # Commande ou URI ouverte dans la session de l'utilisateur avant la capture (via explorer.exe).
    [string]$Open,

    # Délai laissé à la fenêtre pour s'afficher.
    [int]$WaitSeconds = 6
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'TestVM.Common.ps1')
Assert-TestVMAdministrator -HyperVOnly
Add-Type -AssemblyName System.Drawing

if ($Open) {
    $session = New-PSSession -VMName $Name -Credential (Get-TestVMCredential)
    try {
        Invoke-Command -Session $session -ArgumentList $script:TestUserName, $Open -ScriptBlock {
            param($UserName, $Target)
            # Une tâche planifiée interactive est le seul moyen d'afficher une fenêtre dans la session ouverte.
            $action = New-ScheduledTaskAction -Execute 'explorer.exe' -Argument $Target
            $principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$UserName" -LogonType Interactive
            Register-ScheduledTask -TaskName 'OSSetup-Screenshot' -Action $action -Principal $principal -Force | Out-Null
            & schtasks.exe /run /tn 'OSSetup-Screenshot' | Out-Null
            Start-Sleep -Seconds 2
            Unregister-ScheduledTask -TaskName 'OSSetup-Screenshot' -Confirm:$false
        }
    }
    finally {
        Remove-PSSession -Session $session
    }
    Start-Sleep -Seconds $WaitSeconds
}

# Image de l'écran fournie par Hyper-V (RGB 565), à la résolution courante de la VM.
$namespace = 'root\virtualization\v2'
$vm = Get-CimInstance -Namespace $namespace -ClassName Msvm_ComputerSystem -Filter "ElementName='$Name'"
if (-not $vm) { throw "VM introuvable : $Name." }
$head = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_VideoHead | Select-Object -First 1
$width = [int]$head.CurrentHorizontalResolution
$height = [int]$head.CurrentVerticalResolution
$settings = Get-CimAssociatedInstance -InputObject $vm -ResultClassName Msvm_VirtualSystemSettingData |
    Where-Object { $_.VirtualSystemType -eq 'Microsoft:Hyper-V:System:Realized' }
$service = Get-CimInstance -Namespace $namespace -ClassName Msvm_VirtualSystemManagementService
$result = Invoke-CimMethod -InputObject $service -MethodName GetVirtualSystemThumbnailImage `
    -Arguments @{ TargetSystem = $settings; WidthPixels = [uint16]$width; HeightPixels = [uint16]$height }
if ($result.ReturnValue -ne 0) { throw "Capture impossible (code $($result.ReturnValue))." }

$bitmap = [System.Drawing.Bitmap]::new($width, $height, [System.Drawing.Imaging.PixelFormat]::Format16bppRgb565)
$data = $bitmap.LockBits([System.Drawing.Rectangle]::new(0, 0, $width, $height), 'WriteOnly', $bitmap.PixelFormat)
try {
    # Copie ligne par ligne : la largeur de ligne du bitmap (Stride) peut dépasser width * 2.
    for ($y = 0; $y -lt $height; $y++) {
        [System.Runtime.InteropServices.Marshal]::Copy($result.ImageData, $y * $width * 2, [IntPtr]::Add($data.Scan0, $y * $data.Stride), $width * 2)
    }
}
finally {
    $bitmap.UnlockBits($data)
}
$target = [System.IO.Path]::GetFullPath($Path)
New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force | Out-Null
$bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()
Write-TestVMStep "Capture enregistrée : $target"
