# The checkpoint format

A checkpoint is organised by what the next session needs, not by the order things happened.  Resist the urge to narrate.

Copy the template, delete the sections that genuinely do not apply, and fill in the rest.  An empty section heading is worse than no heading, because it implies the question was considered and the answer was nothing.

## Template

```markdown
# Checkpoint - 2026-03-14T1610

Session ID: 8f2c1d40-77ab-4e19-9a3e-5c1e0b2d9f41
Repository: /home/dana/src/invoice-api
Branch: fix/duplicate-invoice-numbers at 4a91c07
Working tree: clean

## What this session was about

## Accomplished

## Decisions and findings

## Out-of-repo changes

## Files created or modified

## Environment

## Pending

## Open items
```

## Header

Everything here is a fact that can be checked, which is the point.  The next session verifies these before trusting anything else in the file.

- **Timestamp** in the heading, matching the filename.  When they disagree, "most recent checkpoint" resolves to the wrong file.
- **Session ID** read from the *current* session.  Never copy it from the checkpoint you restored at the start of this session.
- **Repository** as an absolute path, plus the branch and the short commit hash.
- **Working tree** state.  If it is dirty, say what is uncommitted and whether it is deliberate.

If the working directory is not a repository, say so explicitly and record what the folder name was derived from instead.

## What this session was about

Two or three sentences.  The goal, not the activity.

A reader who stops here should be able to decide whether this checkpoint is relevant to what they are about to do.

## Accomplished

What is **done and verified**, separated from what is merely written.

The distinction is the whole value of the section.  "Added retry logic to the payment client" and "Added retry logic to the payment client, and confirmed it retries three times on a 503 by pointing it at a stub that returns 503 twice" are different claims, and the next session will act on them differently.

State how each item was verified.  If it was not verified, say that plainly:

```markdown
- Rewrote the invoice number generator to use a sequence.  Verified: 10,000 concurrent inserts across 4 connections produced no duplicates.
- Added the migration for the sequence.  NOT run against any database yet.
```

## Decisions and findings

The section a commit log cannot replace, and the one that saves the most time.

Record:

- What was chosen, and what was rejected, and why.  A rejected approach that is not written down gets attempted again.
- What was measured, with the numbers.  "The import is slow" is worth nothing next week.  "The import takes 47 seconds, of which 44 is in the per-row lookup" is worth an hour.
- What turned out to be false.  Assumptions that the work disproved are the most perishable knowledge in a session.
- Anything surprising about the environment or the code.

Be specific enough to be checkable:

```markdown
- Batching the lookups was tried and abandoned.  The API caps a batch at 50 ids, and the import routinely needs 4,000, so the round trips dominate either way.
- The duplicate invoice numbers do not come from concurrency.  They come from the retry path calling the generator a second time after a timeout.  Reproduced by forcing a timeout on the first attempt.
```

## Out-of-repo changes

Anything altered outside version control.  Server configuration, database settings, a cloud console, a scheduled task, a content management system, a DNS record.

These are invisible to `git diff` and will be lost unless written down here.  Full rules and the required fields are in `out-of-repo-changes.md`.

Write these **when you make the change**, not at the end of the session.

## Files created or modified

List the files, including ones outside the project such as scratch scripts and notes.

The project's own diff already lists the tracked files, so add the information the diff lacks: which are throwaway, which are intended to be committed, and which are still uncommitted.

## Environment

The section people skip and then reconstruct painfully.

Record what it took to make the tooling work at all:

- Connection strings and host names, and any that look obvious but are wrong
- Where credentials come from, never the credentials themselves
- Tool paths, versions, and required flags
- Commands that failed and the working form of them

```markdown
- Database: `db-primary.example.com`, port 5432, credentials from the `invoice-api-dev` entry in the OS credential store.
- The test suite needs `--runInBand`.  In parallel it fails on shared fixture state, which looks like a flaky test and is not.
```

A trap recorded here is a trap paid for once.

## Pending

What the next session should do, in the order it should be considered.

Separate:

- **Next step** - the thing to pick up immediately
- **Blocked** - what cannot proceed, and precisely what it is waiting on
- **Deferred** - deliberately not being done, and why, so it is not "fixed" by accident

Say who or what a blocked item is waiting on.  "Blocked on review" is not actionable.  "Blocked until the customer confirms whether historical invoices should be renumbered" is.

## Open items

The task list with status.  See `todos.md` for capturing and restoring it.

If the session tracked no task list, write "None tracked this session" rather than omitting the heading, so the next session knows it was considered.

## Optional sections worth adding

- **Assumptions** - things believed but not verified.  Rare in practice and valuable out of proportion to its length.  An unrecorded assumption is indistinguishable from a fact by the time anyone reads the file.
- **References** - repositories, documents, tickets, and specifications consulted, with enough detail to find them again.
- **Lessons** - process notes worth carrying forward, as distinct from findings about the code.

## Length

Long enough to resume from, short enough to read.

A short session might produce half a page.  A long one with several findings might produce three or four.  If it runs much beyond that, the likely cause is narration: check whether the file is describing what happened rather than what is true now.
