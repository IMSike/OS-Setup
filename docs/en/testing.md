# Testing

## Unit tests and code quality

```powershell
Invoke-Pester -Path tests
```

The [Pester 5](https://pester.dev) tests have no effect on the system (providers are mocked). They also check the data: every item and profile conforms to its schema, every item is documented, and the documentation exists in both languages.

[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) checks the style and common errors of the PowerShell code, with the rules from `PSScriptAnalyzerSettings.psd1` (and `tests/PSScriptAnalyzerSettings.psd1` for the tests; exclusions are justified in the files). The `tests/CodeQuality.Tests.ps1` test runs it when it is installed, and also checks that the module manifest exports all its functions:

```powershell
Install-PSResource PSScriptAnalyzer -Scope CurrentUser
Invoke-Pester -Path tests/CodeQuality.Tests.ps1 -Output Detailed
```

## Hyper-V test VM

Integration tests in a disposable Windows VM, recreatable identically, with no ISO and no clicks. The scripts are in [`tests/vm/`](../../tests/vm/).

Prerequisites on the host: virtualization enabled in the BIOS, the Hyper-V feature, PowerShell 7, Git, a Windows image (`install.esd` or `install.wim`, for example on a USB stick created with the Microsoft media creation tool).

Rights: `New-TestVM.ps1` is run **as administrator** (virtual disks, DISM). `Invoke-TestVM.ps1` and `Reset-TestVM.ps1` run without a UAC prompt if the account is a member of the local **"Hyper-V Administrators"** group (SID `S-1-5-32-578`, effective after logging back in to Windows).

| Script | Role |
|---|---|
| `New-TestVM.ps1` | Creates the VM from the image: virtual disk, edition application (DISM), `unattend.xml`, first logon, then the **"vierge"** ("blank") checkpoint. |
| `Invoke-TestVM.ps1` | Copies the repository's current state (including uncommitted work) into the VM and runs `bootstrap.ps1` there in the user's session, with elevated rights. Brings the logs and backups (including `original-values.json`, the original values) back into `logs/vm/`. |
| `New-TestVMPrerequisite.ps1` | Creates the **"prerequis"** ("prerequisites") checkpoint: real bootstrap from "vierge" (winget, Git, PowerShell 7), a mere simulation of the setup, then a checkpoint of the running VM. The bootstrap trace (installed tools) is kept outside the repository, in `C:\OSSetup-Tests`, and reinjected at each test so that the end-of-setup cleanup behaves as on a real machine. Rerun it when `bootstrap.ps1` changes (`Invoke-TestVM.ps1` points it out). |
| `Reset-TestVM.ps1` | Goes back to the "vierge" checkpoint (default) or "prerequis" (`-Checkpoint prerequis`). |
| `Get-TestVMScreenshot.ps1` | Captures the VM screen as a PNG, optionally after opening a page in the session (`-Open 'ms-settings:privacy-webcam'`): verifies that a setting is **recognized by Windows**, not merely written. |

```powershell
./tests/vm/New-TestVM.ps1 -ImagePath D:\sources\install.esd   # once (10 to 20 min)
./tests/vm/New-TestVMPrerequisite.ps1                         # once, then whenever bootstrap.ps1 changes (6 min)
./tests/vm/Invoke-TestVM.ps1 -Reset -Only privacy, power         # targeted test: these base-profile menus, all checked, the rest empty
./tests/vm/Invoke-TestVM.ps1 -Reset                            # from "prerequis", replays answers/dev.example.json
./tests/vm/Invoke-TestVM.ps1 -Reset -SetupArguments '-AnswerFile','answers\base-all.example.json','-Yes'  # all base-profile settings checked
./tests/vm/Invoke-TestVM.ps1 -Reset -Baseline vierge           # full run from a freshly installed Windows (bootstrap included)
./tests/vm/Invoke-TestVM.ps1 -SetupArguments '-AnswerFile','answers\dev.example.json','-WhatIf'
./tests/vm/Invoke-TestVM.ps1 -Reset -AnswerFile $env:TEMP\t.json # targeted test on a few items: local answer file injected
./tests/vm/Invoke-TestVM.ps1 -Reset -PrepareOnly                # manual test (menus, UAC) of uncommitted work
./tests/vm/Invoke-TestVM.ps1 -Reset -PrepareOnly -AsBootstrapClone  # same, copy treated as created by the bootstrap (end-of-setup cleanup)
```

**Which starting point?** By default, `-Reset` starts again from "prerequis" (3 to 4 min less per test). The full run from "vierge" (`-Baseline vierge`) remains necessary for any change to the bootstrap, and before validating an important step. `-Only` generates `answers/vm-only.json` (in the VM's copy only): for a change limited to a few menus, the test goes from several minutes to next to nothing. Each test displays its total duration.

Reboots requested by the setup are handled: the harness waits for the automatic resume and considers the test finished when `state\last-result.json` exists in the VM.

Automated tests go through an already-elevated scheduled task: they exercise **neither the UAC prompt nor the menus**. For those two, test manually: `-PrepareOnly`, then in the VM console (Hyper-V Manager) run `powershell -NoProfile -ExecutionPolicy Bypass -File C:\OS-Setup\bootstrap.ps1`.

From a console other than this one, pass the arrays with `-Command`: `pwsh -File` would forward `'-AnswerFile','…'` as a single string.

The images and virtual disks are stored outside the repository, in `%ProgramData%\OSSetup-Tests`.

VM account: `tester` / `OSSetup-Test`. This password is **deliberately public**: it only protects a disposable, local VM, and PowerShell Direct refuses accounts without a password.

**WSL 2 and Docker Desktop cannot be tested in the VM** on the current host (AMD processor, Windows 10): Hyper-V does not support nested virtualization there ("this platform does not support nested virtualization" when the VM starts). They are verified on a physical machine; the parts of their setup that do not depend on virtualization (enabling features, reboot, resume) remain testable.
