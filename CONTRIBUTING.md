# Contributing

Thanks for considering a contribution.

## What is most welcome

**A failure mode you have observed, with a real example behind it.**  `references/anti-patterns.md` documents ways checkpoints stop being useful.  Every entry in it was seen more than once in practice.  A speculative entry, however plausible, does not belong there, and a pull request adding one will be asked for the example first.

Also welcome: fixes to the helper scripts, corrections where a document contradicts another, and support for storage layouts the current scripts handle badly.

## Prerequisites

- Git
- PowerShell 5.1 or later, only if you are changing the helper scripts

There is nothing to install and nothing to build.

## Branch model

- `main` is the release branch
- `dev` is the integration branch
- Work happens on `feature/xxx` or `fix/xxx` branches taken from `dev`

Open pull requests against `dev`.  `main` receives changes by merging `dev`.

## Before you commit

Run the repository checks from the repository root:

```powershell
./scripts/Invoke-RepoChecks.ps1
```

It parses every script, verifies each has comment-based help, checks that the two plugin manifests agree, scans for dashes that should be plain hyphens, and looks for identifiers that must not appear in a public repository.  It exits non-zero on any finding.

If you changed a helper script, also exercise it against a scratch directory.  **Never test against a real checkpoint store.**  Pass `-StorageRoot` and point it somewhere disposable.  These scripts create and overwrite files, and someone's working notes are not a test fixture.

## Coding standards

For PowerShell:

- Target PowerShell 5.1, so no PowerShell 7 only syntax such as ternaries or null-coalescing
- Comment-based help with at least `.SYNOPSIS`, plus `[CmdletBinding()]`
- Approved verb-noun naming
- `Set-StrictMode -Version Latest` at the top

Two traps that this repository has already been bitten by, both of which produce a script that works until someone's folder contains exactly one file:

- Under strict mode, `Get-ChildItem` returning a single item yields a scalar, and `.Count` on it throws.  Wrap collection assignments in `@()`.
- Assigning an `if` expression, as in `$x = if ($c) { @(...) }`, sends the result through the pipeline, which unwraps a single-element array and discards the `@()`.  Wrap the whole `if`, not the branches.

For documentation:

- CommonMark, readable unrendered
- No em-dashes or en-dashes.  Use commas, colons, parentheses, or a spaced hyphen ( - )
- Two spaces after a period
- One line per paragraph; do not hard-wrap
- Tables without leading and trailing pipes
- All examples invented.  Never a real host name, database, employer, colleague, or local path

## Pull requests

One logical change per pull request.  Fill in the template.  If you changed behaviour, say how you verified it, and if you did not verify it, say that instead.

See `AGENT-README.md` for the project guardrails.  They apply to human contributors as much as to agents.
