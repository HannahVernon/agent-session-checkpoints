<#
.SYNOPSIS
    Reports unfinished work across every project in a checkpoint store.

.DESCRIPTION
    Reads the most recent checkpoint in each project folder and extracts the
    content under its pending and blocked headings, so work that was started
    and not finished can be found without opening every file.

    This collects; it does not judge.  A project whose latest checkpoint lists
    nothing pending may have been finished, or may simply have stopped being
    recorded, and only a person can tell those apart.

.PARAMETER StorageRoot
    Root directory holding one folder per project.  Defaults to the
    CHECKPOINT_STORAGE_ROOT environment variable, or ~/.agent/session-state.

.PARAMETER OlderThanDays
    Report only projects whose most recent checkpoint is at least this many
    days old.

.PARAMETER IncludeEmpty
    Include projects whose latest checkpoint records no outstanding work.
    Off by default.

.PARAMETER SectionPattern
    Regular expression matching the headings to extract.  Defaults to pending,
    blocked, next steps, remaining and open items.

.EXAMPLE
    Find-OpenWork.ps1
    Lists outstanding work across the whole store, oldest first.

.EXAMPLE
    Find-OpenWork.ps1 -OlderThanDays 30 -IncludeEmpty
    Finds projects untouched for a month, including quiet ones.

.OUTPUTS
    One PSCustomObject per project, with Project, LastCheckpoint, AgeDays,
    Checkpoint and Items.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string] $StorageRoot,

    [Parameter()]
    [int] $OlderThanDays = 0,

    [Parameter()]
    [switch] $IncludeEmpty,

    [Parameter()]
    [string] $SectionPattern = '(pending|blocked|next step|next|remaining|open item|outstanding|todo)'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $StorageRoot)
{
    if ($env:CHECKPOINT_STORAGE_ROOT)
    {
        $StorageRoot = $env:CHECKPOINT_STORAGE_ROOT
    }
    else
    {
        $homeDir     = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
        $StorageRoot = Join-Path $homeDir '.agent/session-state'
    }
}

if (-not (Test-Path -LiteralPath $StorageRoot -PathType Container))
{
    throw "Storage root not found: $StorageRoot"
}

$results = New-Object System.Collections.ArrayList

foreach ($folder in (Get-ChildItem -LiteralPath $StorageRoot -Directory))
{
    $candidates = @(Get-ChildItem -LiteralPath $folder.FullName -Filter 'checkpoint-*.md' -File -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending)

    if ($candidates.Count -eq 0)
    {
        continue
    }

    $latest = $candidates[0]

    if (-not $latest)
    {
        continue
    }

    $stampDate = $latest.LastWriteTime

    if ($latest.Name -match 'checkpoint-(\d{4})-(\d{2})-(\d{2})T(\d{2})(\d{2})')
    {
        try
        {
            $stampDate = Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3] `
                                  -Hour $Matches[4] -Minute $Matches[5] -Second 0
        }
        catch
        {
            $stampDate = $latest.LastWriteTime
        }
    }

    $ageDays = [int] ((Get-Date) - $stampDate).TotalDays

    if ($ageDays -lt $OlderThanDays)
    {
        continue
    }

    $text  = [IO.File]::ReadAllText($latest.FullName)
    $items = New-Object System.Collections.ArrayList

    $sectionMatches = [regex]::Matches(
        $text,
        '(?im)^#{2,3}\s*[^\r\n]*' + $SectionPattern + '[^\r\n]*\r?\n(?<body>[\s\S]*?)(?=\r?\n#{1,3}\s|\z)'
    )

    foreach ($section in $sectionMatches)
    {
        foreach ($line in ($section.Groups['body'].Value -split '\r?\n'))
        {
            $trimmed = $line.Trim()

            if ($trimmed -match '^([-*]|\d+\.)\s+\S')
            {
                $clean = ($trimmed -replace '^([-*]|\d+\.)\s+', '')

                if ($clean.Length -gt 200)
                {
                    $clean = $clean.Substring(0, 197) + '...'
                }

                if ($clean -notmatch '(?i)^(none|n/a|nothing)\b')
                {
                    $null = $items.Add($clean)
                }
            }
        }
    }

    if ($items.Count -eq 0 -and -not $IncludeEmpty)
    {
        continue
    }

    $null = $results.Add([pscustomobject] @{
        Project        = $folder.Name
        LastCheckpoint = $stampDate
        AgeDays        = $ageDays
        Checkpoint     = $latest.FullName
        Items          = $items.ToArray()
    })
}

$results | Sort-Object AgeDays -Descending
