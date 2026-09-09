<#
.SYNOPSIS
    Lints a checkpoint file, or a whole checkpoint store.

.DESCRIPTION
    Checks a checkpoint against the failure modes documented in
    references/anti-patterns.md, all of which produce a file that reads
    perfectly well and is wrong:

      MissingSection    a recommended section heading is absent
      EmptySection      a section heading is present with nothing under it
      TimestampMismatch the filename timestamp disagrees with the one inside
      DuplicateSession  the session identifier appears in another checkpoint
      NoSessionId       no session identifier could be found
      BlockedNoBlocker  an item is marked blocked without saying what for
      Narration         the body reads as a transcript rather than as state

    DuplicateSession is only meaningful when the surrounding folder is
    available, so it is skipped when a single file is checked outside a store.

.PARAMETER Path
    A checkpoint file, or a folder of them.  Defaults to the current location.

.PARAMETER Recurse
    When Path is a folder, check every project subfolder beneath it rather than
    that folder alone.

.PARAMETER RequiredSection
    Section headings that must be present.  Defaults to the recommended set.

.PARAMETER Quiet
    Emit findings only, with no summary line.

.EXAMPLE
    Test-Checkpoint.ps1 -Path .\checkpoint-2026-03-14T1610.md
    Checks one file.

.EXAMPLE
    Test-Checkpoint.ps1 -Path ~/.agent/session-state -Recurse
    Checks an entire store and reports every finding.

.NOTES
    A checkpoint freshly created by New-Checkpoint.ps1 reports EmptySection for
    every heading until it is filled in.  That is intended: an unfilled
    template is an incomplete checkpoint.

.OUTPUTS
    One PSCustomObject per finding, with File, Check, Severity and Detail.
#>
[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string] $Path = (Get-Location).Path,

    [Parameter()]
    [switch] $Recurse,

    [Parameter()]
    [string[]] $RequiredSection = @(
        'What this session was about',
        'Accomplished',
        'Decisions and findings',
        'Files created or modified',
        'Environment',
        'Pending',
        'Open items'
    ),

    [Parameter()]
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path))
{
    throw "Path not found: $Path"
}

$item    = Get-Item -LiteralPath $Path
$targets = @()
$inStore = $false

if ($item.PSIsContainer)
{
    $inStore = $true

    $targets = @(if ($Recurse)
    {
        Get-ChildItem -LiteralPath $Path -Filter 'checkpoint-*.md' -File -Recurse
    }
    else
    {
        Get-ChildItem -LiteralPath $Path -Filter 'checkpoint-*.md' -File
    })
}
else
{
    $targets  = @($item)
    $siblings = @(Get-ChildItem -LiteralPath $item.DirectoryName -Filter 'checkpoint-*.md' -File -ErrorAction SilentlyContinue)
    $inStore  = ($siblings.Count -gt 1)
}

if ($targets.Count -eq 0)
{
    Write-Warning "No checkpoint files found at $Path"
    return
}

$sessionIndex = @{}

if ($inStore)
{
    $scanRoot = if ($item.PSIsContainer) { $Path } else { $item.DirectoryName }

    foreach ($scan in @(Get-ChildItem -LiteralPath $scanRoot -Filter 'checkpoint-*.md' -File -Recurse -ErrorAction SilentlyContinue))
    {
        $scanText = [IO.File]::ReadAllText($scan.FullName)

        if ($scanText -match '(?im)session[ _]?id\s*[:=]?\s*[`*]*\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
        {
            $found = $Matches[1].ToLower()

            if (-not $sessionIndex.ContainsKey($found))
            {
                $sessionIndex[$found] = New-Object System.Collections.ArrayList
            }

            $null = $sessionIndex[$found].Add($scan.FullName)
        }
    }
}

$findings = New-Object System.Collections.ArrayList

function Add-Finding
{
    param (
        [string] $File,
        [string] $Check,
        [string] $Severity,
        [string] $Detail
    )

    $null = $findings.Add([pscustomobject] @{
        File     = $File
        Check    = $Check
        Severity = $Severity
        Detail   = $Detail
    })
}

foreach ($file in $targets)
{
    $text  = [IO.File]::ReadAllText($file.FullName)
    $short = $file.Name

    if ($file.Name -match 'checkpoint-(\d{4}-\d{2}-\d{2})T(\d{4})')
    {
        $fileDate = $Matches[1]
        $fileTime = $Matches[2]

        $head = ($text -split "`n" | Select-Object -First 8) -join ' '

        if ($head -match '(\d{4}-\d{2}-\d{2})[T ](\d{2}):?(\d{2})')
        {
            $bodyDate = $Matches[1]
            $bodyTime = $Matches[2] + $Matches[3]

            if ($bodyDate -ne $fileDate -or $bodyTime -ne $fileTime)
            {
                Add-Finding -File $short -Check 'TimestampMismatch' -Severity 'High' `
                    -Detail "Filename says ${fileDate}T${fileTime}, file says ${bodyDate}T${bodyTime}.  Restore sorts on the filename, so the wrong file can be treated as most recent."
            }
        }
    }

    if ($text -match '(?im)session[ _]?id\s*[:=]?\s*[`*]*\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
    {
        $sid = $Matches[1].ToLower()

        if ($inStore -and $sessionIndex.ContainsKey($sid) -and $sessionIndex[$sid].Count -gt 1)
        {
            $others = @($sessionIndex[$sid] | Where-Object { $_ -ne $file.FullName } | ForEach-Object { Split-Path -Leaf $_ })

            Add-Finding -File $short -Check 'DuplicateSession' -Severity 'High' `
                -Detail "Session id also appears in: $($others -join ', ').  Either the id was copied forward from a restored checkpoint, or one session wrote several files."
        }
    }
    else
    {
        Add-Finding -File $short -Check 'NoSessionId' -Severity 'Low' `
            -Detail 'No session identifier found.  Without it, checkpoints from different sessions cannot be told apart.'
    }

    foreach ($section in $RequiredSection)
    {
        $pattern = '(?im)^#{2,3}\s*' + [regex]::Escape($section)

        if ($text -notmatch $pattern)
        {
            Add-Finding -File $short -Check 'MissingSection' -Severity 'Medium' `
                -Detail "No '$section' heading."
        }
        else
        {
            $body = [regex]::Match($text, $pattern + '(?<body>[\s\S]*?)(?=\r?\n#{2,3}\s|\z)')

            if ($body.Success -and [string]::IsNullOrWhiteSpace($body.Groups['body'].Value))
            {
                Add-Finding -File $short -Check 'EmptySection' -Severity 'Low' `
                    -Detail "'$section' has a heading but no content.  Write 'None' rather than leaving it blank."
            }
        }
    }

    foreach ($line in ($text -split "`r?`n"))
    {
        if ($line -match '(?i)blocked' -and $line -notmatch '(?i)(waiting|until|blocked (on|by)|needs|pending on|depends)')
        {
            if ($line -match '(?i)(status\s*[:=]\s*blocked|^\s*[-*]\s*blocked\b|\|\s*blocked\s*\|)')
            {
                Add-Finding -File $short -Check 'BlockedNoBlocker' -Severity 'Medium' `
                    -Detail "Blocked item does not say what it is waiting on: $($line.Trim())"
            }
        }
    }

    $narrationHits = ([regex]::Matches($text, '(?im)^\s*(then|next|after that)\b|\bthen I\b|\bI then\b')).Count

    if ($narrationHits -ge 4)
    {
        Add-Finding -File $short -Check 'Narration' -Severity 'Low' `
            -Detail "$narrationHits sequencing phrases suggest a transcript rather than a record of current state."
    }
}

$findings

if (-not $Quiet)
{
    $high   = @($findings | Where-Object Severity -eq 'High').Count
    $medium = @($findings | Where-Object Severity -eq 'Medium').Count
    $low    = @($findings | Where-Object Severity -eq 'Low').Count

    Write-Host ''
    Write-Host ("Checked {0} file(s): {1} high, {2} medium, {3} low." -f $targets.Count, $high, $medium, $low)
}
