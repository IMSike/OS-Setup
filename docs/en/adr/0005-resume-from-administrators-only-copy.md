# ADR 0005 — Resume after reboot from an administrators-only copy

- **Status**: accepted
- **Date**: 2026-11-03

## Context

When an item needs a reboot, the setup creates the scheduled task "OS-Setup - reprise" (at logon, highest privileges, no UAC prompt) and resumes at the next logon. Until now this task ran, through the Store execution alias `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`, the repository's `setup.ps1`, with its state in the repository's `state\run.json`. A security audit pointed out that everything this elevated task ran or read could be modified by a program running under the user's account, without elevation:

- the repository (code, catalog, `state\run.json`, `state\bootstrap.json`): a program could replace the code run at the next logon, or the paths that the end-of-setup cleanup deletes;
- the execution alias, in a folder where the user has full control;
- the user's module folders (`Documents\PowerShell\Modules` comes first in `PSModulePath`): a module planted there would be loaded instead of a Windows module;
- the end-of-setup cleanup script and its configuration, written to the user's `%TEMP%` and then run elevated.

Any of these was a bridge to administrator rights without a UAC prompt, lasting from the reboot until the end of the setup (that is, until the next logon if the user postponed the reboot).

Options considered:

- **A. Keep the task and document the risk.** No change, but the bridge remains.
- **B. Run the resume pass without elevation and prompt for UAC.** Closes the hole but breaks the unattended resume (`-Yes`), which is the point of the task.
- **C. Resume from a frozen copy under `%ProgramFiles%`.** Users can only read there; the task runs only files from that folder, with executables found by a path that only administrators control.

Tests in the Windows 10 VM (Store PowerShell 7.6) showed that the Store `pwsh.exe` launched by its package path (`C:\Program Files\WindowsApps\Microsoft.PowerShell_<version>_x64__8wekyb3d8bbwe\pwsh.exe`, owned by TrustedInstaller, read and execute only for users) from a highest-privileges logon task runs elevated, with `Get-ScheduledTask` and the other modules available. Because that path contains the version, it cannot be stored in the task.

## Decision

Option C.

- **Frozen copy.** Before registering the task, the elevated setup copies itself to `%ProgramFiles%\OS-Setup\resume` (`Copy-OSSetupResumeCode`): code, catalog, profiles, schemas, dotfiles, without `.git`, documentation, tests, logs or state, and without the junctions and links at the repository root. The launcher `src\resume.ps1` goes to the root of the copy. The bootstrap trace (`state\bootstrap.json`) is copied to `resume\state`, and `run.json` lives there too. The folder inherits the Program Files permissions: read only for users.
- **Task.** The task runs Windows PowerShell 5.1 from the system folder (`[Environment]::SystemDirectory`, not an environment variable) with `-File "%ProgramFiles%\OS-Setup\resume\resume.ps1"`. The launcher finds the Store `pwsh.exe` in its package folder through the WinRT package API (latest installed version), falling back to the PowerShell 7 MSI under Program Files. It never uses the alias, and it loads no module. It then runs the copy's `setup.ps1 -Resume`.
- **Modules.** With `-Resume`, `setup.ps1` replaces `PSModulePath` before loading any module with a fixed list of administrators-only folders: `$PSHOME\Modules`, `%ProgramFiles%\PowerShell\Modules`, `%ProgramFiles%\WindowsPowerShell\Modules`, `System32\WindowsPowerShell\v1.0\Modules`.
- **User data.** Logs, backups, answers and the last result stay in the repository: `run.json` records its folder (`dataRoot`). The resume pass writes there and reads nothing from it that decides what runs. The end-of-setup cleanup takes its script and the bootstrap trace from the copy.
- **End-of-setup cleanup.** Its script and configuration go to `%ProgramFiles%\OS-Setup\cleanup` (administrators only) instead of `%TEMP%`.
- **Previous versions.** A resume task created by a previous version (repository's `setup.ps1`, `run.json` in the repository) still works once: the state is moved to the copy, and the next task, if any, uses the copy. An unreadable state, or a repository that has disappeared, abandons the resume: task and copy are removed, and the reason is displayed.
- **End.** The copy is removed when the setup finishes, after the cleanup script has been taken from it. `run.json` is written to a temporary file and then renamed, so an interruption never leaves a truncated state.

The Store orphan-task rule (ADR 0004: the `-File` file has `state\run.json` next to it, and the program exists) recognizes the new task without any change.

## Consequences

- During a resume, nothing that is run, nor the state that decides what is run, can be modified without administrator rights.
- One more folder, `%ProgramFiles%\OS-Setup\resume`, exists between the reboot and the end of the setup; `%ProgramFiles%\OS-Setup\cleanup` stays (empty) after the cleanup has run.
- A change made in the repository after the reboot request is not taken into account by the resume pass: it runs the code as it was when the reboot was requested.
- Remaining risk: the elevated resume pass still writes into the user's folders (logs and backups in the repository, history in `%LOCALAPPDATA%\OS-Setup`). A program running as the user could redirect those writes with a junction. Addressed afterwards: during the resume pass, every write into the data folder and the history (log, answers, backups, result) first checks the whole path up to the drive root (`Assert-OSSetupDataPath`, enabled by `Enable-OSSetupDataGuard`). A folder that is a junction or a symbolic link, or a file that is a link (hard links included), stops the write with an error: the resume is abandoned if the repository itself is affected, otherwise the action fails and the run ends with an error. Other reparse points (OneDrive files on demand) are accepted. The history copy also refuses a link inside the backups, which would copy a protected file into a folder the user can read. The end cleanup (`src/cleanup.ps1`) applies the same rule to its log and its deletions. Limits: the interval between the check and the write remains; a repository placed on purpose behind a junction cannot be resumed; the files the items themselves write into the profile (dotfiles, Start layout) are not covered, since writing there is their purpose.
- Outside a resume, an elevated run started by the user (UAC prompt) still runs the repository's code and the user's modules. That is expected: the user chose to run that code elevated.
