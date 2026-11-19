<#
.SYNOPSIS
    Exercises explicit storage and path confinement in a disposable directory.
.PARAMETER ScratchRoot
    An existing scratch directory.  Tests create and remove one named child.
.EXAMPLE
    ./scripts/Test-CheckpointTools.ps1 -ScratchRoot ([IO.Path]::GetTempPath())
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $ScratchRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/session-checkpoints/scripts'
$testRoot = Join-Path (Resolve-Path -LiteralPath $ScratchRoot).Path ('checkpoint-tools-' + [guid]::NewGuid().ToString('N'))
$store = Join-Path $testRoot 'store'
$work = Join-Path $testRoot 'work'
$passed = 0
$oldEnvironment = $env:CHECKPOINT_STORAGE_ROOT

function Assert-Test
{
    param ([bool] $Condition, [string] $Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}

function Assert-Rejected
{
    param ([scriptblock] $Action, [string] $Name)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Test $rejected $Name
}

try
{
    New-Item -ItemType Directory -Path $store, $work -Force | Out-Null
    $env:CHECKPOINT_STORAGE_ROOT = Join-Path $testRoot 'ignored-environment'

    foreach ($name in @('Resolve-CheckpointPath', 'New-Checkpoint', 'Find-OpenWork', 'Test-Checkpoint', 'Update-CheckpointIndex'))
    {
        $command = Get-Command (Join-Path $scriptsPath "$name.ps1")
        $mandatory = @($command.Parameters['StorageRoot'].Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory })
        Assert-Test ($mandatory.Count -gt 0) "$name requires StorageRoot"
    }

    $sessionId = [guid]::NewGuid().ToString()
    $checkpoint = & (Join-Path $scriptsPath 'New-Checkpoint.ps1') -StorageRoot $store -Path $work -FallbackName invoice-api -SessionId $sessionId
    Assert-Test ($checkpoint.Created -and (Test-Path -LiteralPath $checkpoint.Path -PathType Leaf)) 'creates checkpoint in explicit root'
    Assert-Test (-not (Test-Path -LiteralPath $env:CHECKPOINT_STORAGE_ROOT)) 'ignores environment fallback'
    $reused = & (Join-Path $scriptsPath 'New-Checkpoint.ps1') -StorageRoot $store -Path $work -FallbackName invoice-api -SessionId $sessionId
    Assert-Test ($reused.Reused -and $reused.Path -eq $checkpoint.Path) 'reuses same-session checkpoint today'

    $text = [IO.File]::ReadAllText($checkpoint.Path)
    $text = [regex]::Replace($text, '(?m)^(## [^\r\n]+)', '$1' + "`r`n`r`nNone.")
    [IO.File]::WriteAllText($checkpoint.Path, $text, (New-Object Text.UTF8Encoding $false))
    $projectName = $checkpoint.ProjectName
    $relative = Join-Path $projectName (Split-Path -Leaf $checkpoint.Path)
    $findings = @(& (Join-Path $scriptsPath 'Test-Checkpoint.ps1') -StorageRoot $store -RelativePath $relative -Quiet)
    Assert-Test ($findings.Count -eq 0) 'lints a valid relative checkpoint'
    $indexes = @(& (Join-Path $scriptsPath 'Update-CheckpointIndex.ps1') -StorageRoot $store -RelativePath $relative -PassThru)
    Assert-Test ($indexes.Count -eq 1 -and (Test-Path -LiteralPath $indexes[0].Index -PathType Leaf)) 'indexes the checkpoint parent directory'
    $open = @(& (Join-Path $scriptsPath 'Find-OpenWork.ps1') -StorageRoot $store -IncludeEmpty)
    Assert-Test ($open.Count -eq 1 -and $open[0].Project -eq $projectName) 'finds the project in explicit root'
    $all = @(& (Join-Path $scriptsPath 'Test-Checkpoint.ps1') -StorageRoot $store -RelativePath '.' -Recurse -Quiet)
    Assert-Test ($all.Count -eq 0) 'recursive lint stays within root'

    [IO.File]::WriteAllText((Join-Path $testRoot 'outside.md'), $text, (New-Object Text.UTF8Encoding $false))
    foreach ($bad in @('../outside.md', "$projectName/../../outside.md", $checkpoint.Path, "$projectName/file.md:stream", "$projectName/*.md", "$projectName/missing.md"))
    {
        Assert-Rejected { & (Join-Path $scriptsPath 'Test-Checkpoint.ps1') -StorageRoot $store -RelativePath $bad -Quiet } "rejects invalid target $bad"
        Assert-Rejected { & (Join-Path $scriptsPath 'Update-CheckpointIndex.ps1') -StorageRoot $store -RelativePath $bad } "index rejects invalid target $bad"
    }

    $missingWork = Join-Path $work 'not-present'
    Assert-Rejected { & (Join-Path $scriptsPath 'Resolve-CheckpointPath.ps1') -StorageRoot $store -Path $missingWork -FallbackName '..' -Create } 'rejects project traversal'
    Assert-Rejected { & (Join-Path $scriptsPath 'Find-OpenWork.ps1') -StorageRoot $checkpoint.Path } 'rejects file as storage root'
    Assert-Rejected { & (Join-Path $scriptsPath 'Find-OpenWork.ps1') -StorageRoot (Join-Path $testRoot 'missing') } 'rejects nonexistent read root'
    Assert-Rejected { & (Join-Path $scriptsPath 'Find-OpenWork.ps1') -StorageRoot './relative-store' } 'rejects ambiguous relative root'

    $outside = Join-Path $testRoot 'outside'
    New-Item -ItemType Directory -Path $outside | Out-Null
    $link = Join-Path $store 'linked'

    if ([IO.Path]::DirectorySeparatorChar -eq '\')
    {
        New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    }
    else
    {
        New-Item -ItemType SymbolicLink -Path $link -Target $outside | Out-Null
    }

    try
    {
        Assert-Rejected { & (Join-Path $scriptsPath 'Resolve-CheckpointPath.ps1') -StorageRoot $store -Path $missingWork -FallbackName linked -Create } 'rejects linked project'
        Assert-Rejected { & (Join-Path $scriptsPath 'Test-Checkpoint.ps1') -StorageRoot $store -RelativePath '.' -Recurse -Quiet } 'recursive lint rejects directory link'
        Assert-Rejected { & (Join-Path $scriptsPath 'Update-CheckpointIndex.ps1') -StorageRoot $store -RelativePath '.' -Recurse } 'recursive index rejects directory link'
    }
    finally
    {
        [IO.Directory]::Delete($link)
    }

    $outsideFile = Join-Path $outside 'index.md'
    [IO.File]::WriteAllText($outsideFile, 'Outside sentinel.')
    $indexPath = Join-Path (Join-Path $store $projectName) 'index.md'
    Remove-Item -LiteralPath $indexPath -Force
    New-Item -ItemType HardLink -Path $indexPath -Target $outsideFile | Out-Null
    Assert-Rejected { & (Join-Path $scriptsPath 'Update-CheckpointIndex.ps1') -StorageRoot $store -RelativePath $projectName } 'rejects hard-linked index output'
    Assert-Test ([IO.File]::ReadAllText($outsideFile) -eq 'Outside sentinel.') 'preserves outside hard-link target'

    Write-Host "$passed tests passed."
}
finally
{
    $env:CHECKPOINT_STORAGE_ROOT = $oldEnvironment
    if (Test-Path -LiteralPath $testRoot)
    {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
