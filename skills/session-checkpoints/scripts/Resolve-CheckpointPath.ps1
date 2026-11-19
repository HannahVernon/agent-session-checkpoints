<#
.SYNOPSIS
    Resolves the checkpoint folder for a working directory.

.DESCRIPTION
    Derives the project name from the version control root directory name and
    joins it to the checkpoint storage root, producing the folder where that
    project's checkpoints belong.

    The project name is used deliberately in preference to a session
    identifier: a session identifier cannot be known by the session that needs
    to find the folder later, whereas a project name can be computed
    independently by any session working in the same repository.

    When the path is not inside a repository, supply -FallbackName to name the
    folder after the task instead.  Without it, the script reports that no
    repository was found and returns nothing.

.PARAMETER Path
    The working directory to resolve.  Defaults to the current location.

.PARAMETER StorageRoot
    Required explicit root directory holding one folder per project.
    No environment variable or default is used.

.PARAMETER FallbackName
    Folder name to use when Path is not inside a repository.  Use a short
    descriptive name for the task, for example 'log-analysis'.

.PARAMETER Create
    Create the folder if it does not exist.

.EXAMPLE
    Resolve-CheckpointPath.ps1 -StorageRoot ~/agent-session-state
    Resolves the current directory against the specified storage root.

.EXAMPLE
    Resolve-CheckpointPath.ps1 -StorageRoot ~/agent-session-state -Path ./invoice-api -Create
    Resolves and creates the folder for the invoice-api repository.

.EXAMPLE
    Resolve-CheckpointPath.ps1 -StorageRoot ~/agent-session-state -FallbackName 'dns-migration'
    Names the folder for the task when the directory is not a repository.

.OUTPUTS
    System.Management.Automation.PSCustomObject with ProjectName, Path,
    RepositoryRoot and Exists.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string] $Path = (Get-Location).Path,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $StorageRoot,

    [Parameter()]
    [string] $FallbackName,

    [Parameter()]
    [switch] $Create
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'CheckpointStorage.psm1') -Force

function Get-RepositoryRoot
{
    param ([string] $StartPath)

    if (-not (Test-Path -LiteralPath $StartPath))
    {
        return $null
    }

    $current = (Resolve-Path -LiteralPath $StartPath).Path

    if (Test-Path -LiteralPath $current -PathType Leaf)
    {
        $current = Split-Path -Parent $current
    }

    while ($current)
    {
        foreach ($marker in @('.git', '.hg', '.svn'))
        {
            if (Test-Path -LiteralPath (Join-Path $current $marker))
            {
                return $current
            }
        }

        $parent = Split-Path -Parent $current

        if ($parent -eq $current -or [string]::IsNullOrEmpty($parent))
        {
            return $null
        }

        $current = $parent
    }

    return $null
}

$repoRoot    = Get-RepositoryRoot -StartPath $Path
$projectName = $null

if ($repoRoot)
{
    $projectName = Split-Path -Leaf $repoRoot
}
elseif ($FallbackName)
{
    $projectName = $FallbackName
}
else
{
    Write-Warning "No repository found at or above '$Path'.  Supply -FallbackName to name the folder after the task."
    return
}

if ($projectName -match '[\\/]' -or $projectName -in @('.', '..'))
{
    throw 'The project name must be a single directory name.'
}

$resolved = Resolve-CheckpointStoragePath -StorageRoot $StorageRoot -RelativePath $projectName -AllowMissing
$folder = $resolved.Path

if ($resolved.Exists -and -not (Test-Path -LiteralPath $folder -PathType Container))
{
    throw "Project path is not a directory: $folder"
}

if ($Create -and -not $resolved.Exists)
{
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $null = Resolve-CheckpointStoragePath -StorageRoot $resolved.StorageRoot -RelativePath $projectName
    Write-Verbose "Created $folder"
}

[pscustomobject] @{
    ProjectName    = $projectName
    Path           = $folder
    RepositoryRoot = $repoRoot
    Exists         = (Test-Path -LiteralPath $folder -PathType Container)
}
