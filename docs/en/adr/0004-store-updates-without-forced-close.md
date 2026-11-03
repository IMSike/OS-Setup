# ADR 0004 — Store apps updated without forced close (PowerShell 7, Windows Terminal)

- **Status**: accepted
- **Date**: 2026-11-01

## Context

The development profile runs long-lived sessions in PowerShell 7 (herdr panes, coding agents). On 2026-10-26, Windows force-closed them to update PowerShell from the Microsoft Store.

Observed in the test VM (Windows 10 22H2 and Windows 11):

- Windows force-closes a running Store app once its update has been deferred on **at least 3 distinct UTC dates** and the session is **locked**. Windows Terminal is exposed in the same way.
- The MSI build of PowerShell is not affected: Microsoft Update replaces its files without closing sessions. But PowerShell drops the MSI from 7.7 onwards; 7.6 LTS is the last branch to ship one.
- The upstream fix (`UpdateWhileInUse=defer` in the Store package) is ignored by Windows as long as the package keeps an old `MaxVersionTested`, and has no effect on Windows 10.
- The `DoNotUpdate` setting of the MDM provider (`EnterpriseModernAppManagement`, reachable through its WMI bridge `MDM_EnterpriseModernAppManagement_AppManagement01_02`) stops the Store from updating an app on its own. With it, no forced close happened over 3 UTC dates and a locked session.
- When an app is not running, an update requested through the Store API with `AllowForcedAppRestart = false` installs in a few seconds. With `AutomaticallyDownloadAndInstallUpdateIfFound = false`, the Store only reports that an update exists, without downloading it. It answers only while `DoNotUpdate` is lifted, and the request causes neither a deferral nor a close.

## Options considered

1. **MSI + Microsoft Update.** No code, but the delay after a release is unknown (up to two weeks according to the documentation). Microsoft Update never installed it on its own on Windows 11 during the tests. It ends with 7.6 (support until November 2028).
2. **MSI + a SYSTEM task that installs the PowerShell update from Windows Update.** The update delay is under control, but this also ends with 7.6 and depends on Microsoft Update publishing it.
3. **Wait for the upstream fix.** Three conditions are outside our control: raising `MaxVersionTested`, a release, a backport to 7.6. It would also have no effect on Windows 10.
4. **Store build, automatic updates blocked, updates done by scheduled tasks when the app is closed** (chosen).

## Decision

PowerShell 7 is installed from the Store (`winget --source msstore`, product `9MZ1SNWT0N5D`), on Windows 10 and Windows 11, by the bootstrap and by the `pwsh` item. Windows Terminal is installed from the Store too (product `9N0DX20HK701`) by the `windows-terminal` item; a copy from the `winget` source (GitHub release) is the same package (same identity, Store signature) and is kept. Both declare a `store-update-guard` action:

- `DoNotUpdate = 1` for their package family;
- three scheduled tasks, shared by all guarded apps (list in `apps.json`). Scripts live in `%ProgramFiles%\OS-Setup\store-update`: one per task, plus `StoreUpdate.Common.ps1`, the functions all three load (log, installed version, open processes, orphan resume task). Only administrators can modify them, and the setup checks them against the repository by hash, the shared file included since the SYSTEM task runs it too:
  - **`OS-Setup - Store (système)`** (SYSTEM, daily and at logon; authenticated users may run it, not modify it):
    - restores the block if it was lifted;
    - for a closed app: lifts the block, has the update installed without forced close, puts the block back;
    - for a running app: lifts the block only for the time of the Store query, which only checks that an update exists;
    - while a setup resume is pending (task `OS-Setup - reprise`, which starts PowerShell 7 at logon): only checks, even for a closed app. A resume task that will never resume anything is ignored (line in the log): its `setup.ps1`, its executable or `state\run.json` no longer exists (repository moved or deleted, PowerShell removed), or no pass has run for 48 hours (`run.json` is rewritten at each pass). Otherwise an abandoned setup would leave the guarded apps without updates;
    - at each run, records in `open.json` the processes of each app it sees open, in every session (administrator consoles and other accounts included, which the user window cannot see);
  - **`OS-Setup - Store (recherche)`** (user, no trigger): queries the Store on behalf of the user, because the Store API only acts for the calling account;
  - **`OS-Setup - Store (fenêtre)`** (user, at logon then every 15 minutes):
    - has the Store checked at most every 4 hours;
    - when no check of an app has succeeded for more than 14 days, shows at most once a day (even during a delay or a setup resume): "Les mises à jour de <app> n'ont pas pu être vérifiées depuis N jours : voir le journal C:\Program Files\OS-Setup\store-update\store-update.log" ("The updates of <app> could not be checked for N days: see the log …"). The block stays in place;
    - an update pending for a closed app: installs it silently. An app the window sees closed but the SYSTEM task sees open (still running process in `open.json`) is left to the normal 4-hour check, without an hourly SYSTEM run;
    - an update pending for a running app: offers **Update now** or a delay (10 min, 1 h, 5 h, tomorrow);
    - **Update now** first checks with the Store again, and closes nothing if the update is no longer offered. Otherwise it closes the app (and herdr first, which would restart the shell), then updates it;
    - during that check (up to 30 minutes if a SYSTEM run is already in progress), a small window "Vérification auprès du Store…" ("Checking with the Store…") stays on screen with a **Cancel** button. Cancel (or Esc) stops waiting, closes nothing, and asks again in 10 minutes (line in the log);
    - the SYSTEM task is the reference: if, in the `open.json` written during that check, it sees a still running process of the app that the window does not see, nothing is closed (herdr included) and the window shows "Une fenêtre administrateur ou la session d'un autre utilisateur utilise <app> : fermez-la, la mise à jour se fera ensuite." ("An administrator window or another user's session is using <app>: close it, the update will follow."), then asks again in 10 minutes. An `open.json` missing or older than the check is ignored (line in the log).

Files next to the scripts, read-only for users: `apps.json` (guarded apps, written by the setup), `run.json` (request of the SYSTEM task to the search task) and `open.json` (processes seen by the SYSTEM task), written by SYSTEM. Writable by users: `check.json` (check results) and `store-update.log` (shared log). Deleting the folder removes them all.

An existing MSI of PowerShell 7 is uninstalled (`win32-uninstall`) so that a machine already in use ends like a fresh one. The cleanup treats the `Microsoft.PowerShell` identifier recorded by an older bootstrap and the Store product as the same tool.

## Consequences

- No session is closed without the user's consent. Updates follow the Store, including the move to 7.7 (not LTS), which is accepted.
- An update offered while the app runs all day waits for the user's choice or for the next logon. The window repeats the question after the chosen delay.
- During the availability check of a running app, the block is lifted for the time of the Store query (usually a few seconds, at most 3 minutes). The Store may start its own update in that window: the check sees it and cancels it while the app is running, and the window offers it again. Only an update the Store starts after the check and before the block is back would follow its usual rules (deferral, forced close only after 3 dates and a locked session). For a closed app, the block stays lifted during its update (at most 15 minutes).
- Prerequisite: the Microsoft Store, present and reachable. The bootstrap has no other source for PowerShell 7: on an edition without the Store (LTSC, IoT), with the Store removed or blocked, the `msstore` source disabled, or a network that filters the Store, it stops with the error code, the probable causes and what to do.
- **One account per machine.** The user tasks are registered for the account that runs the setup, and the guard checks that account by SID: when the setup is run from another account, the tasks are registered again for that account (the last account wins). The block (`DoNotUpdate`) applies to the whole machine, so **the other accounts no longer get Store updates for PowerShell 7 and Windows Terminal**: the Store no longer updates these apps on its own, and the tasks only query the Store and update them for the account they belong to.
- Under the Store PowerShell, a few engine paths needed adjusting:
  - the package path contains its version, so elevation goes through the execution alias `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`, as soon as it exists, even when the setup was started from a PowerShell 7 MSI; the resume task finds the package folder at each resume instead ([ADR 0005](0005-resume-from-administrators-only-copy.md));
  - the DISM module goes through Windows PowerShell 5.1.
- On an older machine, the setup may run under the PowerShell 7 MSI it must uninstall: `msiexec` would stop it on the spot. That uninstall is postponed until the setup closes and done by the end-of-setup cleanup; if a reboot comes first, the resume pass, under the Store PowerShell, uninstalls the MSI directly.
- How long `DoNotUpdate` holds on a machine not managed by an MDM is not verified over months. The SYSTEM task restores it at each run.
- If the checks keep failing (Store API error, search task that never starts, tasks of another account), the block keeps the apps without updates. Rather than lifting the block, the window warns the user: `check.json` records for each app the date of the last check that succeeded (`lastSuccess`: "up to date", "offered", or installation completed; not an error, nor an `Error` or `Canceled` state, nor a timeout), kept while the following runs fail. Beyond 14 days since that date, or, with no success at all, since `check.json` was created (it is laid with the guard), the warning appears at most once a day. An entry written by an earlier version, without `lastSuccess`, is ignored until the next search writes the field.
- Rollback on a machine: stop and delete the three tasks, set `DoNotUpdate` back to 0, then delete `%ProgramFiles%\OS-Setup\store-update` and each account's `%LOCALAPPDATA%\OS-Setup\store-update.json` (see [`windows/development.md`](../windows/development.md#powershell-7--pwsh)).

## Removal

The guard is a workaround: it is meant to be removed from OS-Setup once Windows no longer force-closes these apps.

**Condition**, all of:

- Windows 10 is no longer supported by OS-Setup (the upstream fix has no effect there);
- the Store PowerShell declares the deferral in a manifest Windows honours: `UpdateWhileInUse=defer` in `(Get-AppxPackageManifest Microsoft.PowerShell).Package.Properties`, and `MaxVersionTested` at least `10.0.26100.0` in `(Get-AppxPackageManifest Microsoft.PowerShell).Package.Dependencies.TargetDeviceFamily`;
- the VM test of the context, redone without the guard on Windows 11: block lifted (`DoNotUpdate = 0`), app running, update deferred on at least 3 distinct UTC dates, session locked; nothing is closed, and event 638 reads "Force update deferred by package: true";
- the same test for Windows Terminal, which already declares the deferral.

**Perimeter to remove**:

- `src/store-update/` (all four scripts), `src/OSSetup/Functions/StoreUpdate.ps1`, `src/providers/store-update-guard.ps1`;
- the `StoreUpdate.ps1` exports in `src/OSSetup/OSSetup.psd1` (`ConvertTo-OSSetupStoreUpdateApp` to `Test-OSSetupStoreUpdateGuard`, `Get-OSSetupAccountSid` included: nothing else uses it);
- the `storeUpdateGuardAction` definition of `schemas/item.schema.json` and its reference in the action list;
- the `store-update-guard` actions of `catalog/dev/pwsh.json` and `catalog/dev/windows-terminal.json`;
- `tests/StoreUpdate.Tests.ps1` and the `src\store-update\…` entries of `tests/CodeQuality.Tests.ps1`;
- in both languages: the `store-update-guard` row of `how-it-works.md`, the "Updates" paragraphs, the guard implications and rollbacks of `pwsh` and `windows-terminal` in `windows/development.md`, the Store tasks in `testing.md`; this ADR becomes "superseded", with the date and the reason;
- the comment of `Get-OSSetupStoreCancelScript` (`src/OSSetup/Functions/System.ps1`) that refers to `StoreUpdate.User.ps1`.

**To keep**: PowerShell 7 and Windows Terminal installed from the Store (bootstrap, `pwsh` and `windows-terminal` items, `source: msstore`); `packageName` and `Test-OSSetupAppxInstalled`; the execution alias (`Get-OSSetupPwshPath`) for elevation, and the resume launcher `src/resume.ps1` (ADR 0005); `Import-OSSetupDismModule`; the uninstall of the PowerShell MSI and its deferral to the setup close; `Stop-OSSetupStoreUpdate` and the `appx` provider; `Invoke-OSSetupUnelevatedCommand`; the entries of `pitfalls.md`.

**Commits** on `dev`, as a starting point. Later commits may have touched the same files: removing the perimeter above in one commit is usually simpler than reverting them one by one, with this list as a guide. Later guard commits come from `git log --oneline -- src/store-update src/OSSetup/Functions/StoreUpdate.ps1 src/providers/store-update-guard.ps1 tests/StoreUpdate.Tests.ps1`.

- Guard only, to revert: `4a6806b`, `e07f7cd`, `61bcb2e`, `374ca07`, `922507c`, `843562c`, `9313766`, `f199320`, `2f4f388`, `3a232e0`, `8932fd7`, `7c57694`, `feff7da`, `a742345`, `ba52c18`, `0089583`, `5d23a37`, `55006a6`, `f30e20b`, `d01f38c`, `20eb245`, `729ed34`, `0b9fa03`, `41e3afe`, `ae1028a`, `b531e5a`, `a728422`, `9fa3539`, `2309e81`, `f0d2209`, `6bd241f`, `82727da`, `d7b5477`, `2ec21f8`.
- Mixed, to undo by hand for the guard part only: `b0a27a8` (introduces the guard, but also the Store install by the bootstrap, the execution alias, `Import-OSSetupDismModule`, the winget `source` and the cleanup that treats the MSI and the Store product as one tool), `85b5236` (PowerShell 7 from the Store and the guard actions of both items), `afb524e` (Windows Terminal from the Store).
- Not to revert, they stay: `33b40f5`, `f63ddd8`, `598fafc`, `fde17a1`, `6043126`, `00cf8e7`, `c37c514`, `a75e8a2`, `107fda0`, `e1ffc5b`, `d9fd440`.

**Leftovers on installed machines**: the three tasks, the `%ProgramFiles%\OS-Setup\store-update` folder, `DoNotUpdate = 1` on both package families, and `%LOCALAPPDATA%\OS-Setup\store-update.json` in each account that ran the setup. Without a cleanup, the Store would never update these apps again. A cleanup step ships before the removal or with it, and stays until every machine has run it:

1. stop then delete the three tasks: the SYSTEM task must not be running any more, or it would put the block back;
2. set `DoNotUpdate` back to 0 for `Microsoft.PowerShell_8wekyb3d8bbwe` and `Microsoft.WindowsTerminal_8wekyb3d8bbwe`;
3. delete `%ProgramFiles%\OS-Setup\store-update` only, never `%ProgramFiles%\OS-Setup`, which also holds other items' files (`docker\`) and the setup's own (`resume\`, `cleanup\`);
4. delete `%LOCALAPPDATA%\OS-Setup\store-update.json` of the account that runs the setup (the copies of other accounts are harmless: nothing reads them any more).
