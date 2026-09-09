# agent-session-checkpoints

A skill that teaches an AI coding agent to write a durable record of a working session, and to restore it at the start of the next one.

An agent session ends and its context is gone.  What was tried and rejected, what was decided and why, which systems were touched outside version control, and what the next step was going to be all go with it.  A commit log does not capture any of that.

This repository packages the convention, the rules that keep it useful, and five optional helper scripts.

## What is in it

```
skills/session-checkpoints/
  SKILL.md                      the skill; the only file an agent must read
  references/
    checkpoint-format.md        the template and per-section rules
    restoring.md                the session-start protocol
    out-of-repo-changes.md      changes that git diff cannot see
    todos.md                    task lists across sessions
    reviewing.md                auditing checkpoints across projects
    anti-patterns.md            observed failure modes
  scripts/                      five optional PowerShell helpers
```

## Installing

### As a plugin

```
/plugin install HannahVernon/agent-session-checkpoints
```

Or add the marketplace first, then browse and install:

```
/plugin marketplace add HannahVernon/agent-session-checkpoints
/plugin marketplace browse hannahvernon
/plugin install agent-session-checkpoints@hannahvernon
```

### As a skill directory

Skills are loaded from several locations, so you can also use the skill without installing a plugin:

- Project: `.github/skills/`, `.agents/skills/`, or `.claude/skills/`
- Personal: `~/.copilot/skills/` or `~/.agents/skills/`
- Custom: any directory registered with `/skills add`

To run it directly from a clone, which is the best option if you intend to modify it:

```
/skills add /path/to/agent-session-checkpoints/skills
/skills reload
```

Point at the `skills` directory, not at `skills/session-checkpoints`.  Nothing is copied, so edits to `SKILL.md` take effect on the next `/skills reload`.

To install it as a personal skill instead, copy `skills/session-checkpoints/` into `~/.copilot/skills/`.

The skill activates on phrases such as "save a checkpoint", "write up where we are", and "pick up where we left off", and on starting work in a project that may have a prior checkpoint.

## The core convention

**Checkpoints live outside the project**, in a storage root such as `~/.agent/session-state/`, so they survive branch deletion and never end up in project history.

**Each project gets a folder named after the project**, derived from the version control root directory name.  Not after the session.  This is the detail that decides whether the system works at all: a session identifier cannot be known by the session that later needs to find the folder, but a project name can be computed by any session working in the same repository.

**One file per session**, named `checkpoint-YYYY-MM-DDTHHMM.md`, updated in place as the session continues.

**Restore verifies before it trusts.**  A checkpoint records what was true when it was written.  Branches move and other people push, so the restore step checks the recorded branch, commit and tree state against reality and reports any discrepancy instead of assuming.

## The helper scripts

All optional.  The skill is written to be followed by hand, because agents run on machines without PowerShell and a rule that requires tooling is a rule that gets skipped.

Script | Does
--- | ---
`Resolve-CheckpointPath.ps1` | Turns a working directory into the correct checkpoint folder path
`New-Checkpoint.ps1` | Creates or reuses this session's file, generating the filename and heading from one clock reading so they cannot disagree
`Test-Checkpoint.ps1` | Lints for missing sections, timestamp mismatches, duplicate session identifiers, blocked items with no blocker, and narration
`Update-CheckpointIndex.ps1` | Regenerates a browsable `index.md` per project
`Find-OpenWork.ps1` | Reports the most recent checkpoint per project and its unfinished items, oldest first

Each supports `-?` for help.  Set `CHECKPOINT_STORAGE_ROOT` to control where the store lives, or pass `-StorageRoot`.

```powershell
# lint an entire store
./skills/session-checkpoints/scripts/Test-Checkpoint.ps1 -Path ~/.agent/session-state -Recurse

# what did I leave unfinished?
./skills/session-checkpoints/scripts/Find-OpenWork.ps1 -OlderThanDays 14
```

## Where the failure modes come from

`references/anti-patterns.md` is derived from auditing several hundred real checkpoints written across dozens of projects over about a year.  Every entry in it was observed more than once, including the ones that produce a file which reads perfectly and is wrong: a session identifier copied forward from the checkpoint that was just restored, a filename timestamp that disagrees with the timestamp inside the file, and work that was written but never run being recorded in the same voice as work that was tested.

Nothing in that file is hypothetical, and speculative entries do not belong in it.

## Contributing

Issues and pull requests are welcome, particularly a failure mode you have observed with a real example behind it.

Before committing, run:

```powershell
./scripts/Invoke-RepoChecks.ps1
```

It parses every script, checks the documentation conventions, verifies the two plugin manifests agree, and scans for identifiers that must not appear in a public repository.

See `AGENT-README.md` for the guardrails, which apply to human contributors just as much as to agents.

## License

MIT.  See `LICENSE`.
