<#
.SYNOPSIS
    Creates this session's checkpoint file, or returns the existing one.

.DESCRIPTION
    Finds the checkpoint folder for the current project and returns the path to
    this session's checkpoint file, creating it from the template when it does
    not yet exist.

    Two failure modes are prevented mechanically rather than by memory:

    A second file for a session.  When a checkpoint in the folder already
    records the supplied session identifier, that file is returned instead of a
    new one being created, so the session updates its existing checkpoint.

    A filename that disagrees with the timestamp inside the file.  Both are
    generated from the same clock reading at creation, so they cannot drift.

.PARAMETER SessionId
    Identifier for the current session.  Read this from the session you are
    actually in.  Never copy it from a checkpoint that was restored at the
    start of the session, because that makes the field identify nothing.

.PARAMETER Path
    Working directory used to resolve the project.  Defaults to the current
    location.

.PARAMETER StorageRoot
    Root directory holding one folder per project.  Defaults to the
    CHECKPOINT_STORAGE_ROOT environment variable, or ~/.agent/session-state.

.PARAMETER FallbackName
    Folder name to use when Path is not inside a repository.

.PARAMETER Title
    Optional short title recorded in the heading alongside the timestamp.

.PARAMETER Force
    Create a new file even when this session already has one.  Use only when
    deliberately starting a separate record, and expect the restore step to
    read only the newest file.

.EXAMPLE
    New-Checkpoint.ps1 -SessionId '8f2c1d40-77ab-4e19-9a3e-5c1e0b2d9f41'
    Creates or reuses the checkpoint for the current repository.

.EXAMPLE
    New-Checkpoint.ps1 -SessionId $id -Title 'Invoice numbering fix'
    Records a title in the heading.

.OUTPUTS
    System.Management.Automation.PSCustomObject with Path, Created, Reused,
    ProjectName and SessionId.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $SessionId,

    [Parameter()]
    [string] $Path = (Get-Location).Path,

    [Parameter()]
    [string] $StorageRoot,

    [Parameter()]
    [string] $FallbackName,

    [Parameter()]
    [string] $Title,

    [Parameter()]
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolver = Join-Path $PSScriptRoot 'Resolve-CheckpointPath.ps1'

if (-not (Test-Path -LiteralPath $resolver))
{
    throw "Resolve-CheckpointPath.ps1 not found beside this script."
}

$resolveArgs = @{ Path = $Path; Create = $true }

if ($StorageRoot)  { $resolveArgs['StorageRoot']  = $StorageRoot }
if ($FallbackName) { $resolveArgs['FallbackName'] = $FallbackName }

$target = & $resolver @resolveArgs

if (-not $target)
{
    throw "Could not resolve a checkpoint folder for '$Path'.  Supply -FallbackName if this is not a repository."
}

$folder = $target.Path

if (-not $Force)
{
    $existing = @(Get-ChildItem -LiteralPath $folder -Filter 'checkpoint-*.md' -File -ErrorAction SilentlyContinue |
                  Sort-Object Name)

    foreach ($candidate in $existing)
    {
        $text = [IO.File]::ReadAllText($candidate.FullName)

        if ($text -match [regex]::Escape($SessionId))
        {
            Write-Verbose "This session already has a checkpoint at $($candidate.FullName)"

            [pscustomobject] @{
                Path        = $candidate.FullName
                Created     = $false
                Reused      = $true
                ProjectName = $target.ProjectName
                SessionId   = $SessionId
            }

            return
        }
    }
}

$now      = Get-Date
$stamp    = $now.ToString('yyyy-MM-ddTHHmm')
$fileName = "checkpoint-$stamp.md"
$fullPath = Join-Path $folder $fileName

$suffix = 1

while (Test-Path -LiteralPath $fullPath)
{
    $fileName = "checkpoint-$stamp-$suffix.md"
    $fullPath = Join-Path $folder $fileName
    $suffix++
}

$heading = "# Checkpoint - $stamp"

if ($Title)
{
    $heading = "# Checkpoint - $stamp - $Title"
}

$branch     = ''
$commit     = ''
$treeState  = ''
$repoRoot   = $target.RepositoryRoot

if ($repoRoot -and (Get-Command git -ErrorAction SilentlyContinue))
{
    Push-Location $repoRoot

    try
    {
        $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
        $commit = (& git rev-parse --short HEAD 2>$null)
        $status = (& git status --porcelain 2>$null)

        $treeState = if ([string]::IsNullOrWhiteSpace(($status | Out-String))) { 'clean' } else { 'has uncommitted changes' }
    }
    finally
    {
        Pop-Location
    }
}

$lines = @(
    $heading
    ''
    "Session ID: $SessionId"
    "Repository: $(if ($repoRoot) { $repoRoot } else { "$Path (not a repository)" })"
    "Branch: $(if ($branch) { "$branch at $commit" } else { 'n/a' })"
    "Working tree: $(if ($treeState) { $treeState } else { 'n/a' })"
    ''
    '## What this session was about'
    ''
    '## Accomplished'
    ''
    '## Decisions and findings'
    ''
    '## Out-of-repo changes'
    ''
    '## Files created or modified'
    ''
    '## Environment'
    ''
    '## Pending'
    ''
    '## Open items'
    ''
)

[IO.File]::WriteAllText($fullPath, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding $false))

Write-Verbose "Created $fullPath"

[pscustomobject] @{
    Path        = $fullPath
    Created     = $true
    Reused      = $false
    ProjectName = $target.ProjectName
    SessionId   = $SessionId
}
