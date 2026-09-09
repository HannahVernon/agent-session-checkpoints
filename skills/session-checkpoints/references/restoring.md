# Restoring a checkpoint

Run this at the **start** of a session, before touching any code.  Restoring after you have already made changes is how a session ends up fighting its own prior state.

## The protocol

### 1. Find the folder

Derive the project folder from the version control root directory name and look for it in the storage root.

```
<storage root>/<project name>/
```

If it does not exist, there is no prior state.  Say so and continue with the work.  Do not go looking for a session-named folder; the convention does not create one.

### 2. Read the most recent file

Sort `checkpoint-*.md` by filename and take the last.  The filename is an ISO-like timestamp, so lexical order is chronological order.

Read the whole file.  Skimming the headings is how the blocked item and the out-of-repo change get missed.

If several files are close together in time, check whether they record the same session identifier.  If they do, the earlier ones are probably supplements rather than superseded state, so read them too.

### 3. Verify before you trust

**The checkpoint records what was true when it was written.  Check it against what is true now.**

- Is the branch the one recorded?
- Is the commit the one recorded, or has the branch moved?
- Is the working tree in the state described?
- Do the files it says exist actually exist?

Report every discrepancy rather than absorbing it quietly.  A checkpoint that says "clean tree at `4a91c07`" against a repository sitting three commits ahead with uncommitted changes means something happened outside the recorded history, and the user is the only one who can explain it.

This step catches the failure mode where a checkpoint is confidently wrong, which is more dangerous than one that is missing.

### 4. Restore the task list

If the checkpoint records open items and the session has task tracking, load them.  See `todos.md`.

### 5. Summarise, then ask

Tell the user, briefly:

- What the previous session was doing
- What it finished
- What is pending or blocked, and on what
- Any discrepancy found in step 3

Then ask whether to continue from there or start on something else.  Do not assume the checkpoint describes today's priority.  Work gets reprioritised between sessions, and the checkpoint has no way to know.

## Reading a checkpoint critically

Weigh the sections differently:

- **Header facts** are checkable.  Check them.
- **Accomplished** items that state how they were verified can be relied on.  Items that do not, cannot.
- **Decisions and findings** are the most valuable content and the least likely to have gone stale, because reasoning ages more slowly than state.
- **Environment** notes are usually still accurate and save the most time.
- **Pending** is the section most likely to be out of date, because it is a plan and plans get overtaken.

## When there is no checkpoint

Say so plainly and start work.  Do not invent prior context, and do not treat an unrelated project's checkpoint as relevant because the folder name looked similar.

Consider writing one at the end of the session, especially if anything was learned that was expensive to learn.

## When the checkpoint is stale

A checkpoint from months ago against a repository that has moved a long way forward is a historical document, not resumable state.

Read it for the decisions and findings, which usually still hold.  Treat its pending items and environment details as claims requiring re-verification.  Say which parts you are relying on.
