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

PowerShell 7 is installed from the Store (`winget --source msstore`, product `9MZ1SNWT0N5D`), on Windows 10 and Windows 11, by the bootstrap and by the `pwsh` item. Windows Terminal stays a Store app. Both declare a `store-update-guard` action:

- `DoNotUpdate = 1` for their package family;
- three scheduled tasks, shared by all guarded apps (list in `apps.json`). Scripts live in `%ProgramFiles%\OS-Setup\store-update`; only administrators can modify them:
  - **`OS-Setup - Store (système)`** (SYSTEM, daily and at logon; authenticated users may run it, not modify it):
    - restores the block if it was lifted;
    - for a closed app: lifts the block, has the update installed without forced close, puts the block back;
    - for a running app: lifts the block only for the time of the Store query, which only checks that an update exists;
    - while a setup resume is pending (task `OS-Setup - reprise`, which starts PowerShell 7 at logon): only checks, even for a closed app;
    - at each run, records in `open.json` the processes of each app it sees open, in every session (administrator consoles and other accounts included, which the user window cannot see);
  - **`OS-Setup - Store (recherche)`** (user, no trigger): queries the Store on behalf of the user, because the Store API only acts for the calling account;
  - **`OS-Setup - Store (fenêtre)`** (user, at logon then every 15 minutes):
    - has the Store checked at most every 4 hours;
    - when no check of an app has succeeded for more than 14 days, shows at most once a day (even during a delay): "Les mises à jour de <app> n'ont pas pu être vérifiées depuis N jours : voir le journal C:\Program Files\OS-Setup\store-update\store-update.log" ("The updates of <app> could not be checked for N days: see the log …"). The block stays in place;
    - an update pending for a closed app: installs it silently. An app the window sees closed but the SYSTEM task sees open (still running process in `open.json`) is left to the normal 4-hour check, without an hourly SYSTEM run;
    - an update pending for a running app: offers **Update now** or a delay (10 min, 1 h, 5 h, tomorrow);
    - **Update now** first checks with the Store again, and closes nothing if the update is no longer offered. Otherwise it closes the app (and herdr first, which would restart the shell), then updates it;
    - during that check (up to 30 minutes if a SYSTEM run is already in progress), a small window "Vérification auprès du Store…" ("Checking with the Store…") stays on screen with a **Cancel** button. Cancel (or Esc) stops waiting, closes nothing, and asks again in 10 minutes (line in the log);
    - the SYSTEM task is the reference: if, in the `open.json` written during that check, it sees a still running process of the app that the window does not see, nothing is closed (herdr included) and the window shows "Une fenêtre administrateur ou la session d'un autre utilisateur utilise <app> : fermez-la, la mise à jour se fera ensuite." ("An administrator window or another user's session is using <app>: close it, the update will follow."), then asks again in 10 minutes. An `open.json` missing or older than the check is ignored (line in the log).

Files next to the scripts, read-only for users: `apps.json` (guarded apps, written by the setup), `run.json` (request of the SYSTEM task to the search task) and `open.json` (processes seen by the SYSTEM task), written by SYSTEM. Writable by users: `check.json` (check results) and `store-update.log` (shared log), writable by users. Deleting the folder removes them all.

An existing MSI of PowerShell 7 is uninstalled (`win32-uninstall`) so that a machine already in use ends like a fresh one. The cleanup treats the `Microsoft.PowerShell` identifier recorded by an older bootstrap and the Store product as the same tool.

## Consequences

- No session is closed without the user's consent. Updates follow the Store, including the move to 7.7 (not LTS), which is accepted.
- An update offered while the app runs all day waits for the user's choice or for the next logon. The window repeats the question after the chosen delay.
- During the availability check of a running app, the block is lifted for the time of the Store query (usually a few seconds, at most 3 minutes). The Store may start its own update in that window: the check sees it and cancels it while the app is running, and the window offers it again. Only an update the Store starts after the check and before the block is back would follow its usual rules (deferral, forced close only after 3 dates and a locked session). For a closed app, the block stays lifted during its update (at most 15 minutes).
- Prerequisite: the Microsoft Store, present and reachable. The bootstrap has no other source for PowerShell 7: on an edition without the Store (LTSC, IoT), with the Store removed or blocked, the `msstore` source disabled, or a network that filters the Store, it stops with the error code, the probable causes and what to do.
- **One account per machine.** The user tasks are registered for the account that runs the setup, and the guard checks that account by SID: when the setup is run from another account, the tasks are registered again for that account (the last account wins). The block (`DoNotUpdate`) applies to the whole machine, so **the other accounts no longer get Store updates for PowerShell 7 and Windows Terminal**: the Store no longer updates these apps on its own, and the tasks only query the Store and update them for the account they belong to.
- Under the Store PowerShell, a few engine paths needed adjusting:
  - the package path contains its version, so the resume task and elevation go through the execution alias `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`, as soon as it exists, even when the setup was started from a PowerShell 7 MSI;
  - the DISM module goes through Windows PowerShell 5.1.
- On an older machine, the setup may run under the PowerShell 7 MSI it must uninstall: `msiexec` would stop it on the spot. That uninstall is postponed until the setup closes and done by the end-of-setup cleanup; if a reboot comes first, the resume pass, under the Store PowerShell, uninstalls the MSI directly.
- How long `DoNotUpdate` holds on a machine not managed by an MDM is not verified over months. The SYSTEM task restores it at each run.
- If the checks keep failing (Store API error, search task that never starts, tasks of another account), the block keeps the apps without updates. Rather than lifting the block, the window warns the user: `check.json` records for each app the date of the last check that succeeded (`lastSuccess`: "up to date", "offered", or installation completed; not an error, nor an `Error` or `Canceled` state, nor a timeout), kept while the following runs fail. Beyond 14 days since that date, or, with no success at all, since `check.json` was created (it is laid with the guard), the warning appears at most once a day. An entry written by an earlier version, without `lastSuccess`, is ignored until the next search writes the field.
- Rollback: delete the three tasks and `%ProgramFiles%\OS-Setup\store-update`, then set `DoNotUpdate` back to 0 (see [`windows/development.md`](../windows/development.md#powershell-7--pwsh)).
