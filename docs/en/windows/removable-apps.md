# Removable apps and components (Windows 10 22H2)

Reference for every removal in the catalog (`catalog/remove/`): what it is, the implications and how to get it back. The common mechanisms are explained in [`../how-it-works.md`](../how-it-works.md).

Inventory taken on a freshly installed Windows 10 22H2 and on a machine already in use. An item absent from the machine is considered compliant: the same catalog serves both.

Legend: **✔** selected by default · **○** offered, unselected by default · **✘** do not remove. Everything that can be removed is chosen in a menu, just like everything that can be installed (checked when the data is loaded).

## Mechanisms

| Type | Provider | What is done | Getting the item back |
|---|---|---|---|
| Store app | `appx` | **Deprovisioning** (otherwise it comes back for every new account), then removal **for all accounts** — in that order, otherwise Windows refuses (0x80073CFA). Under PowerShell 7 / Windows 10, the Appx module goes through Windows PowerShell 5.1. | Microsoft Store, or `winget install --source msstore <name>` |
| Windows component ("capability") | `windows-capability` | `Remove-WindowsCapability`; a restart may be requested. | Settings > Apps > Optional features > Add a feature |
| Windows feature | `windows-feature` (`enabled: false`) | `dism /Disable-Feature`. | Control Panel > Programs > Turn Windows features on or off |
| Classic software | `win32-uninstall` | Uninstaller declared in "Programs and Features", run unattended (MSI: `msiexec /x … /qn`). | Reinstall the software (winget, vendor's site) |

Major Windows updates may reinstall some apps: rerunning the setup removes them again. Before each removal, the original state (packages present) is saved in `original-values.json`.

Warnings: an item whose removal erases local data says so when it is selected (`checkedWarning`), under the menu summary.

---

## Preinstalled apps (menu "Applications préinstallées à supprimer", Preinstalled apps to remove, everything selected)

| Item | App (package) | Implications |
|---|---|---|
| `remove-cortana` | Cortana (`Microsoft.549981C3F5F10`) | None: discontinued, and unavailable in French. |
| `remove-weather` | Weather (`Microsoft.BingWeather`) | No more weather app (the browser remains). |
| `remove-bing` | Bing Search, News (`Microsoft.BingSearch`, `Microsoft.BingNews`) | None; absent from the base image, arrived through updates. |
| `remove-get-help` | Get Help (`Microsoft.GetHelp`) | Windows's "Get help" links lead nowhere anymore. |
| `remove-tips` | Tips (`Microsoft.Getstarted`) | None. |
| `remove-feedback-hub` | Feedback Hub (`Microsoft.WindowsFeedbackHub`) | No more way to send feedback to Microsoft (consistent with the privacy settings). |
| `remove-maps` | Maps (`Microsoft.WindowsMaps`) | No more offline maps. |
| `remove-office-hub` | Office, Microsoft 365 launcher and ad (`Microsoft.MicrosoftOfficeHub`) | None: it is not Office; an installed Office is not touched. |
| `remove-onenote-uwp` | OneNote for Windows 10 (`Microsoft.Office.OneNote`) | Discontinued version. **Warning**: unsynced notes are erased. Office's OneNote is not touched. |
| `remove-solitaire` | Solitaire (`Microsoft.MicrosoftSolitaireCollection`) | None. |
| `remove-3d-viewer` | 3D Viewer (`Microsoft.Microsoft3DViewer`) | 3D files no longer open directly. |
| `remove-paint-3d` | Paint 3D (`Microsoft.MSPaint`) | Classic Paint (`mspaint.exe`) remains. |
| `remove-mixed-reality` | Mixed Reality Portal (`Microsoft.MixedReality.Portal`) | Useless without a mixed reality headset. |
| `remove-people` | People (`Microsoft.People`) | No more Windows address book (used by Mail, also removed). |
| `remove-skype` | Skype (`Microsoft.SkypeApp`) | Service shut down by Microsoft. |
| `remove-wallet` | Wallet (`Microsoft.Wallet`) | None. |
| `remove-your-phone` | Phone Link, cross-device experience (`Microsoft.YourPhone`, `MicrosoftWindows.CrossDevice`) | No more link with a phone (SMS, notifications, photos). |
| `remove-mail-calendar` | Mail and Calendar (`microsoft.windowscommunicationsapps`) | Discontinued: no more sync since the end of 2024. **Warning**: local accounts and data are erased. |
| `remove-new-outlook` | New Outlook for Windows (`Microsoft.OutlookForWindows`) | Replacement for Mail, installed by updates. Third-party accounts (Gmail, IMAP…) go through Microsoft's cloud. Office's ("classic") Outlook is not touched. |
| `remove-groove` | Groove Music (`Microsoft.ZuneMusic`) | Default audio player: audio files then open with Windows Media Player (kept). |
| `remove-movies-tv` | Movies & TV (`Microsoft.ZuneVideo`) | Default video player: same, Windows Media Player. |
| `remove-dev-home` | Dev Home (`Microsoft.Windows.DevHome`) | Discontinued by Microsoft. |
| `remove-onedrive` | OneDrive (classic software) | Uninstallation, then policy `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive` `DisableFileSyncNGSC` = 1: OneDrive is not reinstalled for new accounts and disappears from Explorer. **Warning**: files already synced stay in the OneDrive folder; those that were online-only are no longer accessible from Explorer (still on onedrive.com). To reinstall: delete the policy, then `winget install Microsoft.OneDrive`. |

## Useful apps (menu "Applications utiles à supprimer", Useful apps to remove, nothing selected)

| Item | App (package) | Implications |
|---|---|---|
| `remove-sticky-notes` | Sticky Notes (`Microsoft.MicrosoftStickyNotes`) | **Warning**: unsynced notes are erased. |
| `remove-alarms` | Alarms & Clock (`Microsoft.WindowsAlarms`) | No more timer, stopwatch or alarm. |
| `remove-camera` | Camera (`Microsoft.WindowsCamera`) | No more app for the webcam (video conferencing software is not affected). |
| `remove-sound-recorder` | Voice Recorder (`Microsoft.WindowsSoundRecorder`) | Recordings already made stay in Documents. |
| `remove-calculator` | Calculator (`Microsoft.WindowsCalculator`) | No more calculator. |
| `remove-screen-sketch` | Snip & Sketch (`Microsoft.ScreenSketch`) | **Warning**: `Win+Shift+S` no longer opens the annotation tool. The Snipping Tool remains. |
| `remove-photos` | Photos (`Microsoft.Windows.Photos`) | **Warning**: no more default image viewer (Paint, or a viewer installed by a profile). |

## Xbox (menu "Xbox à supprimer", Xbox to remove, nothing selected)

To be decided with a future gaming profile.

| Item | App (packages) | Implications |
|---|---|---|
| `remove-xbox-app` | Xbox app (`Microsoft.XboxApp`) | No more access to PC Game Pass from this app. |
| `remove-game-bar` | Xbox Game Bar and overlays (`Microsoft.XboxGamingOverlay`, `Microsoft.XboxGameOverlay`, `Microsoft.XboxSpeechToTextOverlay`) | **Warning**: `Win+G` (game captures and recordings) no longer works. |
| `remove-xbox-live` | Xbox Live components (`Microsoft.Xbox.TCUI`, `Microsoft.XboxIdentityProvider`) | **Warning**: some games (Store, Game Pass, Microsoft games) can no longer sign in. |

## Windows components (menu "Composants Windows à retirer", Windows components to remove)

| Item | Default | Component | Implications |
|---|---|---|---|
| `remove-internet-explorer` | ✔ | Internet Explorer 11 (capability `Browser.InternetExplorer`) | Retired by Microsoft since 2023 (it redirects to Edge). The rendering engine used by old applications remains in Windows. |
| `remove-powershell-v2` | ✔ | Windows PowerShell 2.0 (feature `MicrosoftWindowsPowerShellV2Root`) | Obsolete engine that allows bypassing the antivirus (AMSI) and PowerShell logging; removed by Microsoft from recent versions. PowerShell 5.1 and 7 are not affected. |
| `remove-steps-recorder` | ✔ | Steps Recorder (`App.StepsRecorder`) | Recorded clicks and screenshots for technical support; discontinued by Microsoft. |
| `remove-wordpad` | ✔ | WordPad (`Microsoft.Windows.WordPad`) | Discontinued (removed from Windows 11 24H2); `.rtf` files open with an installed word processor. |
| `remove-powershell-ise` | ✔ | PowerShell ISE (`Microsoft.Windows.PowerShell.ISE`) | Old PowerShell 5.1 script editor, with no PowerShell 7 support; replaced by VS Code. |
| `remove-math-input` | ○ | Math Input Panel (`MathRecognizer`) | Pen input of formulas, rarely used. |
| `remove-hello-face` | ✔ | Windows Hello: face recognition (`Hello.Face.*`, the number depends on the Windows version) | Useless without a compatible infrared camera. **Warning**: no more sign-in by face. |
| `remove-quick-assist` | ✔ | Quick Assist (`App.Support.QuickAssist`) | No more built-in remote assistance (Store version available). |
| `remove-fax-scan` | ○ | Windows Fax and Scan (`Print.Fax.Scan`) | **Warning**: some scanners only work with this tool. |
| `remove-print-management` | ✔ | Print Management console (`Print.Management.Console`) | Administration tool for print servers. |
| `remove-work-folders` | ✔ | Work Folders (feature `WorkFolders-Client`) | Corporate file sync, useless for an individual. |
| `remove-smb-direct` | ✔ | SMB Direct (feature `SmbDirect`) | File sharing over RDMA network cards (servers). |
| `remove-xps-printer` | ✔ | Microsoft XPS Document Writer printer (feature `Printing-XPSServices-Features`) | XPS format discontinued; "Microsoft Print to PDF" remains. |

## Never remove (✘)

| Item | Reason |
|---|---|
| App Installer (`Microsoft.DesktopAppInstaller`) and its winget source | **winget**: the setup depends on it |
| Microsoft Store, purchase service | Updates of App Installer and of dependencies |
| HEIF, VP9, WebM, WebP extensions | Codecs (images, videos) |
| fr-FR language pack | Interface language |
| **Edge**, WebView2 | Windows 10: uninstallation not supported (`NoRemove` = 1), reinstalled by updates, parts of Windows open it; WebView2 is used by many applications. Edge will be **neutralized** (startup launch, default browser, pinning, policies) with the browser configuration; full uninstallation to be studied for Windows 11. |
| Windows Media Player | The only remaining player if Groove and Movies & TV are removed, until a player is chosen in a profile |
| Paint, Notepad, Snipping Tool, Remote Desktop, Microsoft Print to PDF, OpenSSH client, languages, .NET | Useful or required by the system |
| System apps (lock screen, Start, Windows Security…) | Windows components |
| Microsoft Update Health Tools, updates (KB) | Windows Update components |
| Driver panels (NVIDIA, Realtek…) | Hardware-specific |
| **Windows PowerShell 5.1** | Part of Windows (not an optional feature); used by system components and by the setup bootstrap. PowerShell 7 will be the default of the `dev` profile. |

## Other findings

- **Sponsored apps** installed automatically (Candy Crush, etc.): prevented by `sponsored-apps-off` (see [`settings.md`](settings.md)). The Start menu keeps **download tiles** (arrow) for the promoted apps of the default layout; they install on first click. To be removed with the Start menu layout (desktop integration).
- **Launch at startup** (VM inventory): OneDrive (removed above), Edge ("startup boost", after its first opening: handled with the browsers), Windows Security (✘, antivirus status), Edge update (✘ as long as Edge remains). The software installed by the setup will get a "do not launch at startup" setting when relevant.
