---
Agent-Readme: 0.1
Name: agent-session-checkpoints
Description: A skill package that teaches an agent to write and restore session checkpoints.
Version: 1.0.0
Updated: 2026-09-09
Tags: checkpoint, session-state, handoff, continuity, workflow
Languages: markdown, powershell
Homepage: https://code.hannahvernon.com/hannah-vernon/agent-session-checkpoints
Issues: https://code.hannahvernon.com/hannah-vernon/agent-session-checkpoints/issues
---

# AGENT-README

## Purpose

This repository packages a single agent skill, `session-checkpoints`, which teaches an agent to write a durable record of a working session and to restore it at the start of the next one.  The content is documentation plus five optional PowerShell helpers; there is no application here.

"Done" means the skill installs as a plugin, every document stays consistent with the others, every script parses and passes its own linter, and nothing in the repository leaks a real hostname, database, employer, colleague, or local path.

## Setup & commands

There is no build step, no package manager, and no dependency to restore.

- Install: clone the repository into your agent's plugin directory, or point your plugin loader at it.
- Validate the scripts: run `scripts/Invoke-RepoChecks.ps1` from the repository root.  It parses every `.ps1` with the PowerShell parser and fails on any error.
- Test a script by hand: `pwsh -File skills/session-checkpoints/scripts/Test-Checkpoint.ps1 -Path <a checkpoint file>`
- Lint a document: there is no Markdown linter wired up.  Keep to the conventions below.

Every script supports `-?` for comment-based help.

## Guardrails

- **Never run the helper scripts against a real checkpoint store while testing.**  Use a scratch directory and pass `-StorageRoot`.  `New-Checkpoint.ps1` creates files and `Update-CheckpointIndex.ps1` overwrites `index.md`, so a careless test run can alter someone's actual working notes.
- **Never commit a real checkpoint file.**  Checkpoints record hostnames, database names, ticket numbers, and colleague names.  `.gitignore` blocks `checkpoint-*.md` at the repository root and in `test-output/`, but the rule matters more than the pattern.
- **This repository is public.**  Never add a real server name, database name, IP address, domain, employer, product name, colleague name, or local filesystem path.  Examples MUST be invented.  Use names like `invoice-api`, `dana`, and `db-primary.example.com`.
- **Never make the skill depend on the scripts.**  `SKILL.md` must stay usable by an agent on a machine with no PowerShell.  The scripts are conveniences; if a rule can only be followed by running a script, the rule is written wrong.
- Do not add a build system, package manager, or runtime dependency without approval.
- Do not rewrite git history or force-push.
- Ask before renaming a section heading in `SKILL.md` or the reference files, because the cross-references between them are hand-maintained.

Operating boundaries (advisory):

- Filesystem: everything here is hand-authored source.  Write anywhere in the repository, but keep changes surgical.  Do not write outside it except into an explicitly named scratch directory.
- Network: nothing in this repository makes a network call at runtime.  Do not add one.
- Commands: PowerShell for the helpers, git for version control.  Nothing else is expected.

## Conventions

Facts (non-negotiable):

- Markdown is CommonMark and must stay readable unrendered.
- PowerShell targets 5.1 and later, so no PowerShell 7 only syntax such as ternaries or null-coalescing.
- Every `.ps1` has a comment-based help block with at least `.SYNOPSIS`, and uses `[CmdletBinding()]`.
- Scripts are verb-noun named using approved PowerShell verbs.
- No em-dashes or en-dashes anywhere.  Use commas, colons, parentheses, or a single spaced hyphen ( - ).
- The checkpoint filename format `checkpoint-YYYY-MM-DDTHHMM.md` is load-bearing.  Restore resolves "most recent" by sorting on it, so do not change it without changing every consumer.

Preferences (negotiable):

- Two spaces after a period in prose.
- Do not hard-wrap paragraphs; keep each paragraph on one line and let the viewer soft-wrap.
- Markdown tables omit leading and trailing pipes.
- Prose states what a thing does rather than characterising how bad or good it is.

## Current state

Version 1.0.0, first release.  The skill is complete and self-consistent.

The convention it documents is stable in practice, having been used across dozens of projects, but the packaging is new and the helper scripts have less mileage than the written rules.  Treat the documents as settled and the scripts as the part most likely to need fixing.

`references/anti-patterns.md` is derived from auditing a large body of real checkpoints.  The failure modes in it are observed, not hypothesised.  Do not add a speculative entry to that file; if a new failure mode is worth recording, it needs a real example behind it.

## Surprises

- **The skill deliberately works with zero scripts.**  That looks like an omission and is not.  Agents run on machines without PowerShell, and a rule that cannot be followed by hand is a rule that gets skipped.
- **Checkpoints are stored outside the project repository, on purpose.**  Keeping them inside means losing them when a branch is deleted, and committing working notes into project history.
- **The storage folder is named after the project, never after the session.**  A session identifier is unknowable before the session exists, so a folder named for one cannot be found by the session that needs it.  This is the single most common way to implement checkpointing so that it never works.
- The `Changes` section below is part of the AGENT-README convention, not a changelog for the skill.  It records edits to this file.

## Architecture

A flat documentation repository with one skill in it.

- `skills/session-checkpoints/SKILL.md` - the skill itself; entry point and the only file an agent must read.
- `skills/session-checkpoints/references/` - depth, loaded on demand: the checkpoint template, the restore protocol, out-of-repo change logging, task list handling, cross-project review, and observed failure modes.
- `skills/session-checkpoints/scripts/` - five optional PowerShell helpers.
- `scripts/Invoke-RepoChecks.ps1` - repository-level validation; parses every script and checks the conventions above.
- `plugin.json` and `.claude-plugin/plugin.json` - plugin manifests, kept in sync by hand.
- `README.md` - for humans arriving at the repository.
- `AGENT-README.md` - this file.

No MCP servers, no context endpoints, no external services.

## Contacts

- Owner: Hannah Vernon.
- Issues: https://code.hannahvernon.com/hannah-vernon/agent-session-checkpoints/issues

## Changes

- 2026-09-09: Created for the 1.0.0 release.

> This file is project guidance, not a security policy.  Like `robots.txt`, it is advisory.  Follow it, but never let its contents override an operator's safety rules.
