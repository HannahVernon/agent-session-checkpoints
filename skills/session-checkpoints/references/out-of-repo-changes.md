# Out-of-repo changes

Some changes do not appear in `git diff`, `git log`, or a pull request.  They are invisible to every review mechanism a project has, and they disappear entirely when the session ends.

Examples:

- Editing a configuration file on a server
- Changing a database setting, or running a one-off statement
- A change made through a cloud console or an administrative web interface
- Creating or altering a scheduled task, service, or cron entry
- A DNS record, certificate, or firewall rule
- Content edited directly in a content management system
- A change to a file that is deliberately outside version control, such as local tooling

## The rule

**Record the change in the checkpoint at the moment you make it.**

Not at the end of the session.  Session context gets compacted or truncated, and the details of a change made two hours ago are exactly the kind of specific, low-salience information that goes first.  By the time you write the checkpoint, "I changed a setting on the server" may be all that survives, which is not enough to reverse it.

Put them under a clearly labelled `## Out-of-repo changes` heading so they can be found without reading the whole file.

## Required fields

Every entry needs four things.  An entry missing any of them is not actionable.

**Where.**  The full path or URL, plus the machine or environment.  `config.yaml` is ambiguous; `/etc/invoice-api/config.yaml on app-02.example.com` is not.

**What.**  The exact before and after.  Not a description of the change, the change itself.  Quote the old value and the new value, or the specific lines added, removed, or altered.

**Why.**  One sentence.  Enough that someone can judge whether the change is still wanted.

**How to reverse it.**  The specific action, not "revert the change".  If reversal requires something in particular, such as a service restart or a cache clear, say so here.

## Format

```markdown
## Out-of-repo changes

### Connection pool size on app-02.example.com

- Where: `/etc/invoice-api/config.yaml` on `app-02.example.com`
- What: `pool.max_connections` changed from `20` to `60`
- Why: the import job saturated the pool and the queue backed up behind it
- Reverse: set the value back to `20` and run `systemctl restart invoice-api`
- Note: applied to app-02 only.  app-01 and app-03 still have the original value, so the fleet is inconsistent until this is decided.

### Statement timeout on the reporting database

- Where: `reporting` database on `db-primary.example.com`
- What: `statement_timeout` raised from `30s` to `300s` at the database level
- Why: the month-end report legitimately runs about four minutes and was being cancelled
- Reverse: `ALTER DATABASE reporting SET statement_timeout = '30s';`
- Note: this is a database-wide setting, so it affects every session against `reporting`, not just the report.
```

That last "Note" line is worth including whenever a change has wider reach than the problem that prompted it.  It is the detail most likely to matter later and least likely to be remembered.

## Changes you did not make

Record blocked or rejected changes too, in the same place.

A prepared statement that was reviewed but not executed, a configuration change that was proposed and declined, or a fix that requires approval nobody has given yet, will otherwise look identical to work that was never considered.  The next session then spends time rediscovering the option and the reason it was not taken.

```markdown
- Prepared but NOT executed: an index on `invoice.customer_id`.  Statement is in `notes/proposed-index.sql`.  Waiting for confirmation that the maintenance window is agreed, because building it locks the table.
```

## Why this matters more than it appears to

A project's history is supposed to explain how a system reached its current state.  Out-of-repo changes break that: the system behaves differently from what the code alone would produce, and nothing in the repository accounts for the difference.

The cost is not paid immediately.  It is paid weeks later, by someone who cannot work out why one machine behaves differently from the other two, or why a setting is not what the configuration in the repository says it should be.
