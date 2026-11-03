# Usage

## On a blank machine

In **Windows PowerShell** (the setup asks for administrator rights only once):

```powershell
cd $env:TEMP
irm https://raw.githubusercontent.com/IMSike/OS-Setup/main/bootstrap.ps1 -OutFile bootstrap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

The setup runs in two stages:

1. **Preparation**: the bootstrap relaunches itself as administrator, installs winget if needed, Git and PowerShell 7, then clones the repository into `%USERPROFILE%\OS-Setup`. Nothing else is installed at this point.
2. **Your choices**: a step-by-step wizard (profiles, software, locations, personal information), then the plan, which you can apply, modify or cancel before anything is changed.

The account used must be an administrator: from a standard account, the setup stops (the settings would go into another account's profile).

The **Microsoft Store** must be present and reachable: PowerShell 7 is installed from the Store. If that fails, the bootstrap shows the error code and the probable causes:

| Cause | What to do |
|---|---|
| Edition without the Store (LTSC, IoT…) | Not supported: use an edition with the Store. |
| Store removed, or blocked by a group policy or a "debloat" tool | Reinstall or unblock the Store, check that it installs an app. |
| `msstore` source disabled in winget | `winget source list`; restore it with `winget source reset --force` (administrator). |
| Network or firewall filtering the Store | Allow the Store or change network. |

Then run the bootstrap again.

### Simulation

`powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -WhatIf` changes nothing: no elevation, no install of winget, Git or PowerShell 7, no clone or update of the repository, no `state\bootstrap.json`. The bootstrap only shows what it would do (each tool present or to install, repository to clone, update or use as is), then runs `setup.ps1 -WhatIf` if PowerShell 7 and a copy of the repository are already there (the copy is used as it is, without `git pull`). Otherwise it stops and explains why: on a blank machine, the setup simulation can only run once the tools and the repository are in place. Run the bootstrap without `-WhatIf` (the plan is shown and must be confirmed before any change), or `./setup.ps1 -WhatIf` from a copy of the repository.

### In the menus

| Key | Effect |
|---|---|
| `↑` `↓` | Move |
| `Space` or `Enter` | Check or uncheck |
| **[ Valider ]** line ("Validate") | Go to the next step |
| `Esc` or **← Retour** line ("Back") | Go back to the previous step |

## From a copy of the repository (PowerShell 7)

```powershell
./setup.ps1                                          # interactive wizard
./setup.ps1 -WhatIf                                  # simulation: plan and simulated actions, nothing is changed
./setup.ps1 -AnswerFile answers/dev.example.json     # replays an answer file, no questions
./setup.ps1 -Profiles base -AcceptDefaults -Yes      # base profile, default values, no questions at all
```

| Parameter | Effect |
|---|---|
| `-AnswerFile <file>` | Replays an answer file: no questions. |
| `-Profiles <names>` | Profiles to apply (skips the profile menu). |
| `-AcceptDefaults` | Default values for choices and variables, instead of the menus. |
| `-SaveAnswers <file>` | Saves the session's answers to this file. |
| `-Yes` | Unattended: applies the plan without confirmation, reboots or logs off without a countdown, closes the window at the end. |
| `-NoPause` | Do not wait for `Enter` before closing the window. |
| `-WhatIf` | Simulation: no changes, no elevation. |

## Answer files

An answer file contains the profiles, the choices of each group and the variables. It is validated by `schemas/answers.schema.json`.

```json
{
  "$schema": "../schemas/answers.schema.json",
  "profiles": ["dev"],
  "choices": {
    "browsers": ["firefox", "vivaldi"],
    "editor": ["vscode"]
  },
  "variables": {
    "DevRoot": "{{UserProfile}}\\Dev"
  }
}
```

A group missing from the file takes its default values. Examples: [`answers/dev.example.json`](../../answers/dev.example.json), [`answers/base-all.example.json`](../../answers/base-all.example.json) (all the settings of the `base` profile).

An option that is no longer offered by its group (for example an item removed from the catalog since the file was saved) is **ignored with a warning** (`Choix 'claude-options' : option 'claude-statusline' inconnue, ignorée.`), and the rest of the file is applied; it is not written back to `state/answers-last.json`. Likewise, a choice group that no profile declares any more (group removed from the catalog) is ignored with a warning (`Groupe de choix 'claude-options' inconnu, ignoré.`). The other inconsistencies still reject the whole file before any action: a group that exists but belongs to none of the selected profiles, too many or too few selections in a group (counted without the ignored options), a file that does not follow the schema.

The answers of each session are saved in `state/answers-last.json`: to replay the same installation on another machine, copy this file **outside the public repository** (it may contain your personal information).

## What the setup leaves on the machine

| Location | Contents |
|---|---|
| `logs/` | Timestamped log of each run |
| `state/answers-last.json` | Answers of the last session |
| `state/backups/<date>/` | Backups of replaced files and `original-values.json` (original values of each modified setting, to roll back by hand) |
| `%ProgramFiles%\OS-Setup\resume\` | Copy of the setup run by the resume task, with `state\run.json` (state of a run waiting for a reboot); deleted at the end of the setup |
| `state/last-result.json` | Summary of the last run |

Apart from the resume copy, these folders are inside the repository copy and ignored by Git. At the end of the setup, if the copy was created by the bootstrap, a menu offers to delete it while keeping the history (log, answers, backups) in `%LOCALAPPDATA%\OS-Setup\<date>`: see [End-of-setup cleanup](architecture.md#end-of-setup-cleanup).

## Reboots and logoff

If an item requires a reboot, the setup saves its state, creates a scheduled resume task and restarts the machine (10 s countdown that a key press postpones). It resumes by itself at the next logon, with no new UAC prompt, running the setup as it was when the reboot was requested (a change made in the repository in between is ignored).

Some settings only take effect at the next logon: the session is then closed at the end of the setup, in the same way.

After the setup ends, the cleanup keeps running for a few minutes in the background: do not restart the machine right away.

## Machine already in use

The setup can be run on a machine in service: each action checks the state before acting, and the plan distinguishes what is already in place (`[ok]`) from what remains to be done. Start with a simulation (`-WhatIf`). Existing configuration files are backed up before being replaced.

## Rolling back

There is no automatic rollback. Each setting is documented with its reverse procedure ([Windows settings](windows/settings.md)), and the original values are in `state/backups/<date>/original-values.json`. See [How the setup changes Windows](how-it-works.md#rollback-and-original-values).
