# Security Policy

## Scope

This repository contains documentation and PowerShell helper scripts.  It has no runtime service, no network calls, and no dependencies.  The realistic security concerns are:

- A helper script writing to or deleting a path it should not.  `New-Checkpoint.ps1` creates files and `Update-CheckpointIndex.ps1` overwrites `index.md`, so a path-handling flaw in either is worth reporting.
- Guidance in the skill that would lead an agent to record a credential, token, or other secret into a checkpoint file.  Checkpoints are written to disk and are frequently synchronised or backed up, so advice that puts a secret into one is a real problem, not a documentation nit.

## Reporting a vulnerability

Report privately to **vuln@mvct.com**.  Please do not open a public issue for a security problem.

Include, as far as you can:

- What the problem is, and which file or script is involved
- The steps to reproduce it
- What an attacker or a careless invocation could achieve
- Your assessment of severity

You can expect an acknowledgement within a few days.  If the report is valid, the fix and a note in the repository history will credit you unless you ask otherwise.

## Supported versions

The most recent release on `main` is the supported version.  There are no long-lived release branches.

## A note on scope

The skill instructs an agent to record environment details in a checkpoint, including host names and where credentials are stored.  **It explicitly instructs the agent never to record the credentials themselves.**  If you find wording anywhere in this repository that could be read as encouraging the opposite, report it.  That is exactly the class of problem this policy exists for.
