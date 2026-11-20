# ADR 0004 — PowerShell 7 installed from the Microsoft Store, fallback to the MSI

- **Status**: accepted
- **Date**: 2026-11-21

## Context

The setup runs under PowerShell 7 ([ADR 0001](0001-engine-language.md)), which the bootstrap installs before launching it, and which the development profile keeps as the working shell (`pwsh` item). Until now it was the MSI (`winget install Microsoft.PowerShell --installer-type wix`), installed machine-wide.

- PowerShell drops the MSI from 7.7 onwards: 7.6 (LTS) is the last branch published in that form. Later versions are only distributed as an MSIX package.
- The MSIX of the `winget` source (GitHub release) is not Store-licensed and cannot be installed machine-wide on Windows 10. The one of the `msstore` source (product `9MZ1SNWT0N5D`) is the Microsoft Store package: it is installed for the current account and the Store updates it.
- A Store package does not behave like an MSI:
  - it is installed **per account**, under `%ProgramFiles%\WindowsApps\Microsoft.PowerShell_<version>_…` (a path that changes on every update), and is started through an execution alias of the account (`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`);
  - `winget list --id 9MZ1SNWT0N5D` answers "installed" when only the MSI is present: winget maps the MSI to the Store product;
  - under this PowerShell, the `Dism` module does not load directly (observed in the VM: the `appx` and `windows-capability` providers failed);
  - the Store may close an open app to update it (observed: update postponed over at least 3 UTC dates and a locked session).
- The Store is not available everywhere: LTSC and IoT editions, Store removed or blocked by a policy, `msstore` source disabled, filtered network.

Options considered:

1. **Stay on the MSI.** Nothing to change, but stuck at 7.6 (supported until November 2028).
2. **Store package, mandatory.** A single variant to maintain, but the bootstrap stops on a machine without the Store while a usable MSI still exists.
3. **Store package, fallback to the MSI when the Store is unavailable** (chosen).

## Decision

Option 3.

- **Intended variant.** PowerShell 7 comes from the Microsoft Store (`winget install --id 9MZ1SNWT0N5D --source msstore`, without `--scope`), for the current account, through the bootstrap and the `pwsh` item. Presence is judged on the account's `Microsoft.PowerShell` appx package, not on `winget list`.
- **Bootstrap.** It installs the Store package and launches `setup.ps1` through the account's execution alias, even if an MSI comes first in `PATH`. If the installation from the Store fails (or the alias does not appear), it displays a warning with the winget code and the likely causes, then installs the PowerShell 7 MSI (or keeps the one already there) and launches the setup with it. It only stops if both fail.
- **`pwsh` item.** Two actions:
  - install the Store package. If winget fails while the MSI ("PowerShell 7-x64") is installed, the action does not fail: it is "ignorée" ("skipped"), with the winget code and the mention of the fallback variant in the summary. It blocks neither the items that depend on `pwsh` nor the exit code, and it is tried again on every run (`fallbackDisplayName`);
  - uninstall the MSI, so that a machine already in use ends up like a new one. It only applies once the Store package is installed for the account (`replacedByPackage`): a machine without the Store keeps its MSI. If the setup runs under that MSI, the uninstallation is done by the end-of-setup cleanup, after the setup has closed.
- **Engine.**
  - The `winget` provider accepts the `msstore` source and an appx package name.
  - The `Dism` module is loaded through Windows PowerShell 5.1 when the setup runs under the Store PowerShell.
  - The elevated relaunch uses the Store alias when it exists, otherwise the running PowerShell.
  - The resume after reboot ([ADR 0005](0005-resume-from-administrators-only-copy.md)) finds the `pwsh.exe` of the Store package through the Windows package API (a folder only administrators can modify), never through the account's alias; failing that, it uses the MSI.
  - The end-of-setup cleanup treats `Microsoft.PowerShell` (MSI recorded by the bootstrap) and `9MZ1SNWT0N5D` as the same tool.
- **Windows Terminal** is still installed from the `winget` source.
- **Updates.** The Store updates PowerShell by itself; the setup does not manage those updates.

## Consequences

- PowerShell 7 follows the Store, including beyond 7.6 (non-LTS versions included).
- The installation is **per account**: another account of the machine has to run the bootstrap to get PowerShell 7. An MSI installed by other means for another account is not affected, unless it is removed by the `pwsh` item (it is installed machine-wide).
- The Store may close open PowerShell sessions to apply a postponed update. Accepted: the development profile restores the working sessions (herdr) after they are closed.
- **Limit of the fallback.** The fallback depends on an MSI existing in winget: it stops at 7.6. When the setup requires a newer version, a machine without the Store will no longer be able to run it, and the fallback will have to be removed or replaced.
- A machine left on the MSI is not in the intended variant: the plan and the summary say so on every run as long as the Store is unavailable. Once the Store is back, one setup run installs the Store package and removes the MSI.
- A scheduled task of the SYSTEM account cannot use this PowerShell (per-account package): the resume stays a task of the user, started by Windows PowerShell 5.1.
- Two variants have to be tested (Store, fallback) as long as the fallback exists.
