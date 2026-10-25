# ADR 0003 — Application configurations: in-house deployment

- **Status**: accepted
- **Date**: 2026-10-20

## Context

The setup must deploy tool configurations (Claude Code, herdr, Git, PowerShell, terminal, editor…), sometimes in non-standard locations, and different depending on the OS and the machine.

chezmoi was considered (templates, diff, cross-platform) but rejected: it adds a piece of software on the target machine, a template syntax and naming conventions to learn, for a need that the engine can cover simply.

## Decision

The engine itself deploys the files in `dotfiles/`. Each catalog item declares, in its `configure` step, a list of files:

| Field | Role |
|---|---|
| `source` | Relative path in `dotfiles/` |
| `target` | Destination path, with variables (e.g. `{{UserProfile}}/.claude/settings.json`) |
| `mode` | `copy` (copied as is), `template` (replacement of `{{Name}}` variables), `merge-json` (deep merge into an existing JSON) |
| `when` | Optional condition (OS, profile, machine…) |

Rules:

- **Deliberately simple templates**: variable substitution only, no logic. One variant per OS = a distinct source file selected by `when`.
- **`merge-json`** for files that applications rewrite themselves (e.g. `settings.json`): the repository only contains the managed keys, the machine's other keys are kept.
- **Idempotence**: the expected content is compared with the present content; only differing files appear in the plan.
- **Diff**: the plan displays the differences before applying.
- **Backup**: any existing file that is modified is first copied to `state/backups/<timestamp>/` (same tree).
- **Capture** (later): reverse command to bring back into the repository a config modified on the machine (except `template` mode).

## Migrating existing data

Before deployment, the engine runs the `migrate` steps declared by the items:

- detect an existing location different from the target location;
- back up, then move / rename (e.g. Claude Code memory folders, whose name derives from the project path);
- record the operation in the log and the plan (`review` if ambiguous).

**User data** (Claude Code memories, histories…) are not dotfiles and never go into this public repository. They may live in a **second, private repository**, to be designed later.

## Consequences

- No additional software on the target machine.
- The deployment code is in the engine (`file` provider) and tested (Pester): copy, template, JSON merge (`merge-json`, first use: Chrome installation preferences) and backup are done; the diff displayed before replacement remains to be written.
- Advanced needs (secrets, logic in templates) will have to be handled case by case; if their number grows, reassess a dedicated tool.
