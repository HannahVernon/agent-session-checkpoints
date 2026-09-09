# Failure modes

These are drawn from auditing a large body of real checkpoints written across dozens of projects over about a year.  Every entry below was observed, more than once.  None are hypothetical.

They are ordered by cost, starting with the ones that make a checkpoint useless rather than merely worse.

## 1. Naming the folder after the session

**The failure.**  Checkpoints are stored in a folder named for the session that produced them.

**Why it is fatal.**  The next session has a different identifier.  It cannot construct the path to the previous session's folder, because it has no way to know what the previous session was called.  The checkpoints are written correctly, stored durably, and never read again.

**How you notice.**  A store containing many folders, each with one checkpoint in it, none of them ever restored.

**Instead.**  Name the folder for the project, derived from the version control root directory name.  It is stable, and both sessions can compute it independently.

## 2. Copying the session identifier forward

**The failure.**  The session restores a checkpoint, then writes its own checkpoint and copies the session identifier out of the file it just read.

**Why it matters.**  The field stops identifying anything.  One identifier ends up spread across files written weeks apart, so it is no longer possible to tell which work happened in which session, whether two files are supplements or successors, or how much was done in a sitting.  It is a quiet corruption, because every individual file looks well formed.

**How you notice.**  The same identifier in checkpoints whose timestamps are days or weeks apart, **combined with** body text that refers to earlier work in the past tense as though it belonged to another session.  The identifier alone is not enough: a long-lived session resumed over several days shares an identifier across files quite legitimately.  What gives the copying away is a file describing "previous sessions" while claiming to be one of them.

**Instead.**  Read the identifier from the current session, every time.  If it is genuinely unavailable, write `unknown` rather than an inherited value.  An empty field is honest; a wrong one is not.

## 3. Filename and in-file timestamps disagreeing

**The failure.**  A file named `checkpoint-2026-03-14T1610.md` whose heading says `2026-03-15T1707`.

**Why it matters.**  Restore resolves "most recent" by sorting filenames.  When the filename is wrong, the wrong file is restored, and because the content is plausible there is no sign that anything is amiss.  This produces confidently stale state, which costs more than missing state.

**How it happens.**  A file created at the start of a session and updated at the end, with only the heading refreshed.  Or a filename typed by hand from memory.

**Instead.**  Generate the filename from the clock, not by hand, and make the heading match.  If a session runs past midnight, keep the original filename and note the actual times in the body.

## 4. A second file for the same day

**The failure.**  More work happens in the same sitting, so a second checkpoint file gets created rather than the existing one being updated.

**Why it matters.**  Restore reads the most recent file only.  Anything recorded in the earlier one, including out-of-repo changes and blocked items, is not read.

**Instead.**  One file per working day.  Update it in place as the day goes on.

**Not to be confused with** the legitimate case: a long-lived session resumed across several days writes one file per day, and the same session identifier appears in each.  That is expected and correct.  The problem is two files covering the same day, not two files sharing an identifier.

## 5. Two naming conventions in one folder

**The failure.**  A folder containing both `checkpoint-2026-03-14T1610.md` and a differently named series, for example sequentially numbered files from another tool.

**Why it matters.**  "Most recent" is now ambiguous, and which convention wins depends on how the sort is implemented.  Whichever set is not matched by the pattern becomes invisible.

**Instead.**  One convention per folder.  If a second system writes into the same location, either give it its own subdirectory or make the restore step explicitly aware of both.

## 6. Narrating instead of recording state

**The failure.**  The checkpoint reads chronologically: "First I looked at the config, then I ran the tests, then I noticed the timeout, then I tried increasing the pool size."

**Why it matters.**  It is a transcript.  The reader has to reconstruct the current state by replaying the story and tracking what is still true at the end, and the narrative form actively hides the answer.

**How you notice.**  Sentences beginning "then", and past-tense verbs describing activity rather than outcomes.

**Instead.**  Write what is true now, organised by what the next session needs.  "The pool size is 60 on app-02 and 20 on the other two nodes" is state.  "I tried increasing the pool size" is narration.

## 7. Recording unverified work as accomplished

**The failure.**  Work that was written but never run appears in the same list, in the same voice, as work that was tested.

**Why it matters.**  The next session builds on it, and finds out the hard way.  This is the failure mode most likely to cause real damage, because it is acted upon with confidence.

**Instead.**  State how each item was verified.  Where it was not, say so in the same sentence.  "Migration written, NOT run against any database" costs four words.

## 8. Omitting the environment section

**The failure.**  No record of connection details, tool versions, required flags, or the commands that did not work.

**Why it matters.**  This is expensive to reconstruct and trivial to record.  It is also the information least likely to be recoverable from anywhere else, because it lives in the shell history of a session that no longer exists.

**How you notice.**  A later session spending its first twenty minutes rediscovering that a test suite needs a particular flag.

**Instead.**  Record the working invocation, and record the traps.  A trap written down is paid for once.

## 9. Omitting out-of-repo changes

**The failure.**  The checkpoint records the code changes and nothing else, while the session also changed a server setting, a database option, or a scheduled task.

**Why it matters.**  Those changes are invisible to every review mechanism the project has.  Nothing else in the world records them.  See `out-of-repo-changes.md`.

**Instead.**  Record them as you make them, with where, what, why, and how to reverse.

## 10. Blocked items with no named blocker

**The failure.**  `Status: blocked` with no statement of what would unblock it.

**Why it matters.**  The item cannot be re-evaluated.  Nobody can tell whether the blocker cleared, so it stays blocked in the record permanently.

**Instead.**  Name the specific thing being waited on and, where relevant, who owns it.  "Blocked until the maintenance window on the 14th is confirmed" can be checked.  "Blocked" cannot.

## 11. Deleting completed items

**The failure.**  Finished work is removed from the task list to keep it tidy.

**Why it matters.**  The record of what has already been tried disappears with it, and the checkpoint stops showing progress.  A list containing only unfinished work suggests nothing is happening.

**Instead.**  Keep completed items, summarising them if the list gets long.

## 12. Writing the checkpoint too late

**The failure.**  Waiting until the session is nearly over, or until after context has been compacted.

**Why it matters.**  A checkpoint written from a truncated context is written from a summary of a summary.  The specific details, exact values, the command that worked, the thing that was ruled out, are exactly what gets dropped first, and exactly what makes a checkpoint worth having.

**Instead.**  Record out-of-repo changes and significant findings as they happen.  Assemble the rest at the end.

## The pattern behind most of these

Several of the entries above share a root cause: **a checkpoint that looks well formed is assumed to be correct.**

A wrong session identifier, a mismatched timestamp, a stale blocked item, and an unverified claim recorded as done all produce a file that reads perfectly.  Nothing about it invites suspicion.  That is precisely why the restore protocol requires verifying the header facts against the repository before trusting anything else in the file.
