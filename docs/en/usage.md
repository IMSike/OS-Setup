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

### Simulation

`powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -WhatIf` changes nothing on the system: no elevation, no install of winget, Git or PowerShell 7, no clone or update of the repository, no `state\bootstrap.json`. The bootstrap only shows what it would do (each tool present or to install, repository to clone, update or use as is; with `-Branch`, whether the existing copy would be switched to that branch or the bootstrap would stop on local changes, read with `git rev-parse` and `git status` only), then runs `setup.ps1 -WhatIf` if PowerShell 7 and a copy of the repository are already there (the copy is used as it is, without `git pull`; like any simulation, it still writes its log, `state/answers-last.json` and `state/last-result.json` in that copy). Otherwise it stops and explains why: on a blank machine, the setup simulation can only run once the tools and the repository are in place. Run the bootstrap without `-WhatIf` (the plan is shown and must be confirmed before any change), or `./setup.ps1 -WhatIf` from a copy of the repository.

### Bootstrap parameters

| Parameter | Effect |
|---|---|
| `-RepoUrl <url>` | Repository to clone (default: `https://github.com/IMSike/OS-Setup.git`). Only used for a new clone. |
| `-Branch <name>` | Branch to clone (default: `main`). A copy already in `-Destination` is switched to it only if it has no local changes, otherwise the bootstrap stops without changing anything; without `-Branch`, that copy stays on its current branch. |
| `-Destination <folder>` | Folder of the repository copy (default: `%USERPROFILE%\OS-Setup`): cloned there, or updated (`git pull --ff-only`) if a copy is already there. |
| `-NoPause` | Do not wait for `Enter` before closing the administrator window opened by the bootstrap. |
| other arguments | Passed on to `setup.ps1` (e.g. `-AnswerFile <file>`, `-Profiles base,dev`, `-Yes`). `-WhatIf` is recognized in every form PowerShell accepts (an unambiguous prefix such as `-WhatI`, the `-wi` alias, any case, a typographic dash `–` or `—` copied from a web page) and turns the bootstrap into a simulation; `setup.ps1` then receives a plain `-WhatIf`. In doubt, it is a simulation: `-WhatIf:$false` too. |

When the bootstrap is run from a copy of the repository (a `setup.ps1` next to it), that copy is used as it is: `-RepoUrl`, `-Branch` and `-Destination` have no effect (a message says so for `-Branch`).

### In the menus

| Key | Effect |
|---|---|
| `↑` `↓` | Move |
| `Space` or `Enter` | Check or uncheck |
| **[ Valider ]** line ("Validate") | Go to the next step |
| `Esc` or **← Retour** line ("Back") | Go back to the previous step |

The answers that belong only to a profile unchecked afterwards (its choice groups, its locations and personal information) are dropped without a message: they are neither applied nor saved.

## From a copy of the repository (PowerShell 7)

```powershell
./setup.ps1                                          # interactive wizard
./setup.ps1 -WhatIf                                  # simulation: plan and simulated actions, nothing is changed on the system
./setup.ps1 -AnswerFile answers/dev.example.json     # replays an answer file, without the wizard
./setup.ps1 -Profiles base -AcceptDefaults -Yes      # base profile, default values, no questions at all
```

| Parameter | Effect |
|---|---|
| `-AnswerFile <file>` | Replays an answer file instead of the wizard. Without `-Yes`, the plan validation screen is still shown (apply, modify a step or cancel) and manual steps are still guided. |
| `-Profiles <names>` | Profiles to apply (skips the profile menu), separated by commas: `-Profiles base,dev`, also through `pwsh -File`. |
| `-AcceptDefaults` | Default values for choices and variables, instead of the menus. Requires `-Profiles`. |
| `-SaveAnswers <file>` | Saves the session's answers to this file. |
| `-Yes` | Unattended: applies the plan without confirmation, reboots or logs off without a countdown, closes the window at the end. |
| `-NoPause` | Do not wait for `Enter` before closing the window. |
| `-WhatIf` | Simulation: nothing is changed on the system, no elevation. The log (`logs/`), `state/answers-last.json` and `state/last-result.json` are still written in the repository copy, as is the `-SaveAnswers` file. |

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

An option that is no longer offered by its group (for example an item removed from the catalog since the file was saved) is **ignored with a warning** (`Choix 'claude-options' : option 'claude-statusline' inconnue, ignorée.`), and the rest of the file is applied; it is not written back to `state/answers-last.json`. Likewise, a choice group that no profile declares (for example a group removed from the profiles since the file was saved) is ignored with a warning (`Groupe de choix 'old-group' inconnu, ignoré.`), and so is a variable that none of the selected profiles declares (`Variable 'DevRot' déclarée par aucun profil choisi, ignorée.`). Group, option and variable names are case-sensitive, like JSON keys. The other inconsistencies still reject the whole file before any action: a group that exists but belongs to none of the selected profiles, too many or too few selections in a group (counted without the ignored options), a variable named like a built-in variable (`UserProfile`, `ProgramFiles`…), a file that does not follow the schema.

The answers of each session are saved in `state/answers-last.json`: to replay the same installation on another machine, copy this file **outside the public repository** (it may contain your personal information).

## What the setup leaves on the machine

| Location | Contents |
|---|---|
| `logs/` | Timestamped log of each run |
| `state/answers-last.json` | Answers of the last session |
| `state/backups/<date>/` | Backups of replaced files and `original-values.json` (original values of each modified setting, to roll back by hand) |
| `%ProgramFiles%\OS-Setup\resume\` | Copy of the setup run by the resume task, with `state\run.json` (state of a run waiting for a reboot); deleted at the end of the setup |
| `state/last-result.json` | Result of the last finished run, simulation included: identifier, exit code, end time |
| `state/bootstrap.json` | Written by the bootstrap: tools it installed, whether it cloned the copy, path of its script (read by the end-of-setup cleanup) |

Apart from the resume copy, these folders are inside the repository copy and ignored by Git. At the end of the setup, if the copy was created by the bootstrap, a menu offers to delete it while keeping the history (log, answers, backups) in `%LOCALAPPDATA%\OS-Setup\<date>`: see [End-of-setup cleanup](architecture.md#end-of-setup-cleanup).

## Reboots and logoff

If an item requires a reboot, the setup saves its state, creates a scheduled resume task and restarts the machine (10 s countdown that a key press postpones). It resumes by itself at the next logon, with no new UAC prompt, running the setup as it was when the reboot was requested (a change made in the repository in between is ignored).

The automatic resume only runs the Microsoft Store PowerShell 7 installed for the account, or failing that the one installed by its MSI (`%ProgramFiles%\PowerShell\7\pwsh.exe`): see [ADR 0005](adr/0005-resume-from-administrators-only-copy.md). With only a PowerShell 7 from elsewhere (zip archive, .NET tool…), the setup creates no resume task: it still restarts the machine, and asks you in the log to run it again by hand afterwards with the same choices (`./setup.ps1 -AnswerFile state\answers-last.json`).

Some settings only take effect at the next logon: the session is then closed at the end of the setup, in the same way.

After the setup ends, the cleanup keeps running for a few minutes in the background: do not restart the machine right away.

## Machine already in use

The setup can be run on a machine in service: each action checks the state before acting, and the plan distinguishes what is already in place (`[ok]`) from what remains to be done. Start with a simulation (`-WhatIf`). Existing configuration files are backed up before being replaced.

## Rolling back

There is no automatic rollback. Each setting is documented with its reverse procedure ([Windows settings](windows/settings.md)), and the original values are in `state/backups/<date>/original-values.json`. See [How the setup changes Windows](how-it-works.md#rollback-and-original-values).
