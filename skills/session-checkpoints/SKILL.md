---
name: session-checkpoints
description: Write and restore session checkpoints so work survives the end of a session. Use when the user says "save a checkpoint", "checkpoint this", "write up where we are", or "pick up where we left off", when starting work in a repository that may have a prior checkpoint, and before any context compaction or long break. Also covers logging changes that git diff cannot see, and auditing checkpoints across projects.
---

# Session checkpoints

A session ends and its context is gone.  Everything you learned, ruled out, decided, and half-finished goes with it unless you wrote it down somewhere durable.  A checkpoint is that written record.

The failure this prevents is not forgetting *what* was done.  A commit log covers that.  It is forgetting **what was tried and rejected, what was decided and why, which of the user's systems were touched outside version control, and what the next step was going to be.**  None of that is in the diff.

Write every checkpoint for a reader who has no memory of the session, because that is exactly who reads it.

## The one rule that matters most

**A checkpoint is not a summary of the conversation.  It is the state required to resume the work.**

Those produce very different documents.  A conversation summary is chronological and describes what was said.  A resumable state is organised by what the next session needs and describes what is true now.  If a section does not help someone continue the work, it does not belong.

## When to write one

Write a checkpoint when:

- The user asks for one, in any wording: "save a checkpoint", "checkpoint this", "write up where we are", "save state"
- Context compaction is approaching, or the session has run long
- You are about to do something risky or irreversible, so there is a record of the state before it
- Work is being handed to someone else
- You made a change outside version control (see `references/out-of-repo-changes.md`, which is time-sensitive and cannot wait for the end of the session)

Do not wait to be asked when the session is about to end or compact.  A checkpoint written after the context is gone is written from nothing.

## Where it goes

Two decisions, and the second is the one people get wrong.

**The storage root** is a durable location outside any project repository, for example `~/.agent/session-state/` or `~/.config/agent/checkpoints/`.  Keep it out of the project so checkpoints are not lost when a branch is deleted, and not accidentally committed to the project's history.  Pick one root and use it for every project.

**The project folder** inside that root is named after the project, **not after the session**.  Derive it from the version control root directory name, so a repository at `/home/dana/src/invoice-api` stores its checkpoints in `<root>/invoice-api/`.

Naming the folder after the session ID is the most common mistake, and it defeats the entire purpose.  Session IDs are unknowable in advance, so the next session cannot find the folder.  A project name is stable, predictable, and is what you actually have on hand when you start work.

If the working directory is not in a repository, use a short descriptive name for the task instead, such as `log-analysis` or `dns-migration`.  Record in the checkpoint that this is what you did and why, so the next session is not confused about the missing repository.

`scripts/Resolve-CheckpointPath.ps1` performs this resolution if PowerShell is available.  It is not required; the rule is simple enough to apply by hand.

## One file per session

Within a single session, **reuse the same file**.  Update it, append to it, rewrite sections of it.  Do not create a second file because more work happened.

Start a **new** file at the start of a **new** session, named:

```
checkpoint-YYYY-MM-DDTHHMM.md
```

Use the current local time, and make the timestamp inside the file agree with the one in the filename.  When those disagree, "most recent checkpoint" resolves to the wrong file, and the next session restores stale state without any sign that it did.

## Writing one

Read `references/checkpoint-format.md` for the template and the rules for each section.  The short version, in the order the next session will want them:

1. **Header** - timestamp, session identifier, project, branch, commit, whether the tree is clean
2. **What this session was about** - the goal, in a few sentences
3. **Accomplished** - what is done and verified, distinguished from what is merely written
4. **Decisions and findings** - what was chosen, what was ruled out, and the reasoning
5. **Out-of-repo changes** - anything altered outside version control, with how to reverse it
6. **Files created or modified** - including files outside the project
7. **Environment** - connection strings, hosts, credentials locations, tool paths, and the traps hit
8. **Pending** - what is next, what is blocked, and on what
9. **Open items** - the task list, with status

Sections 5 and 7 are the ones most often skipped and the most expensive to reconstruct.  Section 4 is what makes the difference between a checkpoint and a commit log.

## Restoring one

At the **start** of every session, before doing any work, check the storage root for a folder matching the current project.  If checkpoints exist, read the most recent one by filename timestamp.

Then, in order:

1. Summarise the prior state to the user: what was in progress, what is pending, key context
2. Restore the task list, if the prior session kept one
3. **Verify the recorded state against reality** rather than trusting it.  Check the branch, the commit, and whether the tree is clean.  Report any discrepancy instead of assuming the checkpoint is still accurate
4. Ask whether to continue from there or start fresh

Step 3 is not optional.  A checkpoint records what was true when it was written.  Branches move, work gets committed elsewhere, and other people push.  Treat the checkpoint as a claim to be verified, not as current fact.

Full protocol in `references/restoring.md`.

## What a checkpoint must not become

- **A transcript.** If it reads chronologically as "then I tried, then I ran, then I noticed", it is a conversation summary, not resumable state.
- **A list of file names with no reasoning.** The diff already lists the files.  Record why.
- **Optimistic.** Work that is written but not verified is not accomplished.  Say which is which.
- **Silent about the parts you are unsure of.** Uncertainty that goes unrecorded gets rediscovered the hard way.  Write down what you assumed and did not verify.

## Failure modes

`references/anti-patterns.md` documents the ways checkpoints stop being useful, drawn from several hundred real checkpoints across dozens of projects.  The three most damaging:

- **Copying the session identifier forward** from the checkpoint you just restored, which makes the field meaningless and makes it impossible to tell later which work happened in which session
- **A filename timestamp that disagrees with the timestamp in the file**, which breaks "read the most recent one"
- **Recording only the code changes**, leaving changes made to servers, databases, cloud consoles, and configuration files undocumented and unreversible

Read that file before writing your first checkpoint.  Every entry in it is cheaper to avoid than to recover from.

## Optional helper scripts

Everything above works with no tooling.  The scripts are conveniences, all PowerShell, all usable independently:

Script | Does
--- | ---
`Resolve-CheckpointPath.ps1` | Turns a working directory into the correct checkpoint folder path
`New-Checkpoint.ps1` | Creates or reuses this session's checkpoint file from the template
`Test-Checkpoint.ps1` | Lints a checkpoint for missing sections, timestamp mismatches, and duplicate session identifiers
`Update-CheckpointIndex.ps1` | Regenerates a browsable `index.md` for a project folder
`Find-OpenWork.ps1` | Reports the most recent checkpoint per project and its unfinished items, oldest first

Run any of them with `-?` for usage.  If PowerShell is not available, apply the rules by hand; nothing in this skill depends on the scripts.

## Reference files

Resolve these against this skill's directory, not the working directory.

File | Read it when
--- | ---
`references/checkpoint-format.md` | Writing a checkpoint, for the template and per-section rules
`references/restoring.md` | Starting a session, for the restore protocol
`references/out-of-repo-changes.md` | You changed anything outside version control
`references/todos.md` | Capturing and restoring a task list across sessions
`references/reviewing.md` | Auditing checkpoints across many projects to find dropped work
`references/anti-patterns.md` | Before writing your first checkpoint, and when one turns out to be unusable
