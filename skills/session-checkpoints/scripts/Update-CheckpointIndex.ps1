<#
.SYNOPSIS
    Regenerates a browsable index.md for a checkpoint folder.

.DESCRIPTION
    Writes an index.md listing every checkpoint in a project folder, newest
    first, with its date, title and size.  The index is generated, so it is
    safe to delete and rebuild at any time.

    The title is taken from the first level one heading in each file, with the
    leading "Checkpoint - <timestamp>" removed when present, so the listing
    shows what a checkpoint was about rather than repeating its date.

.PARAMETER Path
    A project folder containing checkpoint files, or a storage root when used
    with -Recurse.  Defaults to the current location.

.PARAMETER Recurse
    Treat Path as a storage root and rebuild the index in every project
    subfolder beneath it.

.PARAMETER PassThru
    Emit the path of each index written.

.EXAMPLE
    Update-CheckpointIndex.ps1 -Path ~/.agent/session-state/invoice-api
    Rebuilds the index for one project.

.EXAMPLE
    Update-CheckpointIndex.ps1 -Path ~/.agent/session-state -Recurse
    Rebuilds every project index in the store.

.NOTES
    index.md is overwritten without prompting.  Do not keep hand-written notes
    in it.
#>
[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string] $Path = (Get-Location).Path,

    [Parameter()]
    [switch] $Recurse,

    [Parameter()]
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Container))
{
    throw "Folder not found: $Path"
}

$folders = @()

if ($Recurse)
{
    $folders = @(Get-ChildItem -LiteralPath $Path -Directory |
                 Where-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'checkpoint-*.md' -File -ErrorAction SilentlyContinue })
}
else
{
    $folders = @(Get-Item -LiteralPath $Path)
}

if ($folders.Count -eq 0)
{
    Write-Warning "No folders containing checkpoints found under $Path"
    return
}

foreach ($folder in $folders)
{
    $files = @(Get-ChildItem -LiteralPath $folder.FullName -Filter 'checkpoint-*.md' -File |
               Sort-Object Name -Descending)

    if ($files.Count -eq 0)
    {
        Write-Verbose "No checkpoints in $($folder.FullName)"
        continue
    }

    $lines = New-Object System.Collections.ArrayList

    $null = $lines.Add("# Checkpoints for $($folder.Name)")
    $null = $lines.Add('')
    $null = $lines.Add("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm').  Do not edit; this file is rebuilt by Update-CheckpointIndex.ps1.")
    $null = $lines.Add('')
    $null = $lines.Add("$($files.Count) checkpoint(s), newest first.")
    $null = $lines.Add('')
    $null = $lines.Add('date | file | title | size')
    $null = $lines.Add('--- | --- | --- | ---')

    foreach ($file in $files)
    {
        $stamp = ''

        if ($file.Name -match 'checkpoint-(\d{4}-\d{2}-\d{2})T(\d{2})(\d{2})')
        {
            $stamp = "$($Matches[1]) $($Matches[2]):$($Matches[3])"
        }

        $title = ''
        $first = Get-Content -LiteralPath $file.FullName -TotalCount 20 |
                 Where-Object { $_ -match '^#\s+\S' } |
                 Select-Object -First 1

        if ($first)
        {
            $title = ($first -replace '^#\s+', '').Trim()
            $title = ($title -replace '^Checkpoint\s*[-:]?\s*\d{4}-\d{2}-\d{2}T?\d{0,4}\s*[-:]?\s*', '').Trim()
        }

        if (-not $title)
        {
            $title = '(no title)'
        }

        $title = $title.Replace('|', '\|')
        $size  = '{0:N1} KB' -f ($file.Length / 1KB)

        $null = $lines.Add("$stamp | [$($file.Name)]($($file.Name)) | $title | $size")
    }

    $null = $lines.Add('')

    $indexPath = Join-Path $folder.FullName 'index.md'

    [IO.File]::WriteAllText($indexPath, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding $false))

    Write-Verbose "Wrote $indexPath"

    if ($PassThru)
    {
        [pscustomobject] @{
            Folder      = $folder.Name
            Index       = $indexPath
            Checkpoints = $files.Count
        }
    }
}
