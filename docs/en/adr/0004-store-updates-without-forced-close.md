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
  - **`OS-Setup - Store (recherche)`** (user, no trigger): queries the Store on behalf of the user, because the Store API only acts for the calling account;
  - **`OS-Setup - Store (fenêtre)`** (user, at logon then every 15 minutes):
    - has the Store checked at most every 4 hours;
    - an update pending for a closed app: installs it silently;
    - an update pending for a running app: offers **Update now** or a delay (10 min, 1 h, 5 h, tomorrow);
    - **Update now** first checks with the Store again, and closes nothing if the update is no longer offered. Otherwise it closes the app (and herdr first, which would restart the shell), then updates it.

An existing MSI of PowerShell 7 is uninstalled (`win32-uninstall`) so that a machine already in use ends like a fresh one. The cleanup treats the `Microsoft.PowerShell` identifier recorded by an older bootstrap and the Store product as the same tool.

## Consequences

- No session is closed without the user's consent. Updates follow the Store, including the move to 7.7 (not LTS), which is accepted.
- An update offered while the app runs all day waits for the user's choice or for the next logon. The window repeats the question after the chosen delay.
- During the availability check of a running app, the block is lifted for a few seconds. The Store may start its own update in that window: the check sees it and cancels it while the app is running, and the window offers it again. Only an update the Store starts after the check and before the block is back would follow its usual rules (deferral, forced close only after 3 dates and a locked session).
- The user tasks are registered for the account that runs the setup.
- Under the Store PowerShell, a few engine paths needed adjusting:
  - the package path contains its version, so the resume task and elevation go through the execution alias `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`;
  - the DISM module goes through Windows PowerShell 5.1.
- How long `DoNotUpdate` holds on a machine not managed by an MDM is not verified over months. The SYSTEM task restores it at each run.
- Rollback: delete the three tasks and `%ProgramFiles%\OS-Setup\store-update`, then set `DoNotUpdate` back to 0 (see [`windows/development.md`](../windows/development.md#powershell-7--pwsh)).
