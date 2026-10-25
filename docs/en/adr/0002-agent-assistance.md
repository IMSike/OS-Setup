# ADR 0002 — AI agent involvement in the setup

- **Status**: proposed
- **Date**: 2026-10-20

## Context

The setup must work on a blank machine, but also on a machine **already in use**: software installed outside winget,
non-standard locations, existing configurations (Claude Code, etc.) to preserve or merge.
These cases are too varied to all be coded deterministically.

## Decision

The engine remains **deterministic and autonomous**; the agent is an **optional layer** that handles uncovered cases.

1. **Audit** (`setup -Audit`): the engine inventories what exists (winget packages, installation locations, existing config files, settings already applied) and writes a JSON report (`state/audit-<date>.json`).
2. **Plan**: the engine compares the audit with the user's choices and produces a JSON plan where each step is `ok` (already compliant), `todo` (automatic action) or `review` (conflict / unknown case).
3. **Agent assistance** (`setup -Assist`, optional): an agent (Claude Code in non-interactive mode) receives the plan and only handles the `review` steps. It **proposes** resolutions (e.g. a piece of software's actual location, merging an existing config) in the form of a completed answer file.
4. **Human validation**: the agent's proposals are displayed and must be approved before execution. Execution always goes through the engine (same logging, same `-WhatIf`).

A catalog item can also declare a `verify` step with an instruction intended for the agent (e.g. "check that Claude Code sees the configured MCPs"), run only in `-Assist` mode.

## Consequences

- The setup remains usable without an agent or a connection to an AI service.
- The agent never acts directly on the system: it produces data that the engine executes.
- Assistance is **situational** (it may never be used). If it is required, the engine first installs Claude Code **and its configuration**, then pauses and asks the user to sign in (`claude` → login) before taking control back.
- Exact format of the audit report and the plan: to be defined with the JSON schemas.
