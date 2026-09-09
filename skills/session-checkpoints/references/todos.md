# Task lists across sessions

A task list is the cheapest form of continuity available, and the most frequently dropped.  Of the standard checkpoint sections it is the one most often missing, which is unfortunate because it is the one that answers "what now?" without any reading.

## Capturing

Record every open item, with:

- A stable identifier, so it can be referred to later without ambiguity
- A title describing the work
- A status: pending, in progress, done, or blocked
- Enough description that the item makes sense with no memory of the conversation
- For blocked items, what specifically is being waited on

The description is where these usually fail.  An item reading `fix the timeout` is worthless in a week.  The test is whether someone could act on it having read nothing else.

```markdown
## Open items

id | title | status | detail
--- | --- | --- | ---
`seq-migration` | Run the invoice sequence migration | blocked | Migration file is `db/migrations/0043_invoice_seq.sql`, reviewed and correct.  Waiting on a maintenance window because it rewrites the table.
`retry-double-call` | Stop the retry path double-calling the generator | in progress | Cause is confirmed: `PaymentClient.retry()` calls `nextInvoiceNumber()` again instead of reusing the value.  Fix is to hoist the call above the retry loop.
`import-batching` | Batch the import lookups | deferred | Tried and abandoned this session.  The API caps a batch at 50 ids and the import needs about 4,000, so round trips dominate either way.  Do not retry without a bulk endpoint.
```

Note the deferred item.  Recording what was rejected, and why, prevents the next session from repeating the experiment.

## Include what was finished

Keep completed items in the checkpoint rather than deleting them.

Completed items are evidence.  They tell the next session what has already been tried, and they let anyone reading the file reconstruct progress across several sessions.  A list of only the unfinished work implies nothing has happened.

If the list is long, summarise the finished items and give the open ones in full.

## Restoring

At the start of a session, after reading the checkpoint:

1. Load the open items into whatever task tracking the session has
2. Preserve the identifiers so the two sessions can be compared
3. Re-check anything marked blocked, because the blocker may have cleared while nobody was looking
4. Tell the user what was restored, and flag anything that has gone stale

Step 3 matters.  A blocked item stays blocked in the record indefinitely, including long after the thing it was waiting on has arrived.  Nothing updates it on its own.

## If the session tracked nothing

Write `None tracked this session.` under the heading.

An empty heading and an absent heading look the same to a reader, and both raise the question of whether the section was forgotten.  One word removes the doubt.
