# Reviewing checkpoints across projects

Once checkpoints accumulate across many projects, the store becomes a record of everything that was started and not finished.  Reading it periodically surfaces work that was dropped rather than decided against.

This is worth doing when returning from time away, when planning a week, or when the question is "what am I forgetting?".

## What to produce

For each project, the latest checkpoint and its unfinished work.  Sorted by how long it has been sitting.

```markdown
## Open work by project

### invoice-api  (last checkpoint 2 days ago)
- Blocked: sequence migration, waiting on a maintenance window
- Next: hoist the generator call above the retry loop

### customer-portal  (last checkpoint 6 weeks ago)
- Deferred: accessibility contrast fixes on the settings page
- Note: the branch `fix/contrast` still exists and is 11 commits behind main

### log-analysis  (last checkpoint 4 months ago)
- Nothing outstanding recorded.  Probably finished; the checkpoint does not say so.
```

That last entry is the honest form for a common case.  A checkpoint that records no pending work is not the same as one that records completion, and the difference is worth stating rather than resolving by assumption.

## How to read the results

Sort by staleness, but do not treat stale as unimportant.  Age indicates how long something has been ignored, not whether it matters.  The two most interesting categories are:

- **Blocked items that are old.**  The blocker has often cleared and nothing updated the record.  These are frequently ready to proceed.
- **Out-of-repo changes that were never reversed.**  A temporary configuration change made to get past a problem is easy to forget, and the checkpoint may be the only record that it happened.  These deserve a specific pass.

## Time-sensitive items first

If anything in the review has a deadline, an expiry, or a person waiting on it, lead with that and say so.  A certificate expiring, a colleague waiting on an answer, or a credential that was exposed and needs rotating outranks a tidy summary of everything else.

## Where to put the output

Write the review to its own checkpoint, in a folder named for the task rather than a project, since a review spans projects and belongs to none of them.

Record which files were read.  A later review can then tell what had already been considered.

## Automating the collection

`scripts/Find-OpenWork.ps1` gathers the raw material: the most recent checkpoint per project, its age, and the lines under its pending and blocked headings.

It collects, it does not judge.  Deciding what matters, and noticing that a four month old checkpoint means the work was probably finished without being recorded, is the part that needs reading.
