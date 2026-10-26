# Known pitfalls

Behaviors observed during development, and how the engine handles them. Read before changing a provider or adding an item.

## winget (Windows 10, winget 1.29)

| Symptom | Cause and handling |
|---|---|
| `0x8A150019` "requires administrator privileges" | The package requires a winget that is **already elevated** (the installer does not elevate itself). The provider relaunches winget in elevated mode (`Start-Process -Verb RunAs`). |
| `0x8A150113` on a `--scope machine` installation | **MSIX** package: machine-wide installation is not supported on Windows 10. Force another installer (`installerType`, e.g. `wix` for PowerShell 7) or switch to `scope: user`. |
| `0x8A15002B` | Already installed, no applicable update: treated as a success. |
| Package not detected right after a successful installation | Installer that finishes in the background (Squirrel: Discord). The provider waits up to 60 s for `winget list` to find it. |
| Tool not found right after its installation | The session PATH is frozen: the engine reloads it from the registry after each installation (`Update-SessionPath` in the bootstrap). |
| Installed program that does not start, code `-1073741515` (`0xC0000135`) with no message | Missing DLL, most often the Visual C++ runtime (absent from a fresh Windows, rarely declared by portable packages, e.g. rtk): `vcredist` dependency. |
| Package missing from winget (e.g. NVIDIA App) | Would need another provider (direct download), to be validated before adding one. |
| Corrupted accents in captured output (`Trouv├®`) | winget writes UTF-8: set `[Console]::OutputEncoding` to UTF-8 for the duration of the call. |
| Package found in the `msstore` source instead of `winget` | Always specify `--source winget`. |
| Store version (MSIX) of a piece of software already present: `winget list --id` recognizes it, and its app execution alias (`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`) answers `Get-Command` (observed: PowerShell 7, whose processes the Store force-closes on each update, herdr sessions included) | Rely neither on the command nor on winget: check the file of the wanted installation (`installedPath`, the bootstrap's `-Path`), force the installer (`--force`), start the setup through that full path, then remove the Store version (`appx` provider). `setup.ps1` refuses to run in the Store pwsh. |
| Installed package that `winget list --id` does not find (`0x8A150014`), while `winget list --name` shows it with its identifier (observed: PowerShell 7 updated by Microsoft Update) | The plan wanted to reinstall it. `winget export` does make the link: second opinion in `Test-OSSetupWingetInstalled`. |

Under Windows PowerShell 5.1, do not capture or redirect winget's output (`| Out-Host`, assignment): it would be decoded with the OEM code page. Let it write directly to the console, or set `[Console]::OutputEncoding` to UTF-8.

## Windows

- `New-Item -Force` on an **existing** registry key recreates it empty: all its values are lost. Create a key only if it does not exist (`if (-not (Test-Path …)) { New-Item … }`).
- Removing a Store app for all accounts (`Remove-AppxPackage -AllUsers`) fails (`0x80073CFA`) as long as it is provisioned: deprovision it first (`Remove-AppxProvisionedPackage`).
- Under PowerShell 7 and Windows 10, the Appx module does not load ("Operation is not supported on this platform"): `Import-Module Appx -UseWindowsPowerShell` routes it through Windows PowerShell 5.1 (`Import-OSSetupAppxModule`, deserialized objects). Under `-WhatIf`, this load fails (copying the compatibility module's files is simulated): force `$global:WhatIfPreference = $false` for the duration of the import, then restore it.
- On a blank machine, `Install-PSResource` fails until the PSResourceGet configuration exists; a first `Get-PSResourceRepository` initializes it.
- The output of system tools (`powercfg`, `dism`…) depends on the language: only read stable values (hexadecimal numbers, `dism /English`).

## PowerShell

- Windows PowerShell 5.1 reads a `.ps1` file **without a BOM** as ANSI: accented characters are corrupted. `.ps1`, `.psm1` and `.psd1` files are UTF-8 with BOM (fixed in `.gitattributes` and `.editorconfig`).
- Variable names are case-insensitive: a local variable `$answers` overwrites the `$Answers` parameter.
- Typographic apostrophes `‘ ’` are equivalent to `'` and quotes `“ ”` to `"`: a text containing `’` (e.g. French `powercfg` output) goes between straight quotes `"…"`.
- `$x = if (...) { @() }` gives `$null`, and a one-element array becomes the element: write `$x = @(if (...) { ... })`.
- An advanced script (`[CmdletBinding()]`) that forwards its remaining arguments (`ValueFromRemainingArguments`) must declare `[CmdletBinding(PositionalBinding = $false)]`: otherwise an argument such as `-WhatIf` meant for `setup.ps1` is captured positionally by another parameter.

## Test VM

- winget is unusable in a PowerShell Direct session: execution goes through a scheduled task in the logged-on session.
- `Start-ScheduledTask` fails silently there: use `schtasks /run`.
