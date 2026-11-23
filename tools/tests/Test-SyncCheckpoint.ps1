<#
.SYNOPSIS
    Tests checkpoint sync against disposable local Git repositories.
.PARAMETER ScratchRoot
    An existing scratch directory.  The test removes only its own named child.
.PARAMETER CheckpointScriptsPath
    Directory containing the portable checkpoint scripts under test.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string] $ScratchRoot,

    [Parameter(Mandatory)]
    [string] $CheckpointScriptsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path (Resolve-Path -LiteralPath $ScratchRoot).Path ('checkpoint-sync-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $testRoot 'work'
$remote = Join-Path $testRoot 'origin.git'
$wrapper = Join-Path (Split-Path -Parent $PSScriptRoot) 'Sync-Checkpoint.ps1'
$passed = 0

function Invoke-TestGit
{
    param ([string[]] $GitArguments)
    $output = @(& git --no-pager -C $script:repo @GitArguments)
    if ($LASTEXITCODE -ne 0) { throw "Git test setup failed: $($GitArguments -join ' ')" }
    $output
}

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
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $null = & git init --bare $remote
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create local bare test repository.' }
    $null = Invoke-TestGit @('init', '-b', 'main')
    $repo = ((Invoke-TestGit @('rev-parse', '--show-toplevel')) -join '').Replace('/', [IO.Path]::DirectorySeparatorChar)
    $null = Invoke-TestGit @('config', 'user.name', 'Checkpoint tests')
    $null = Invoke-TestGit @('config', 'user.email', 'checkpoint-tests@example.invalid')
    $null = Invoke-TestGit @('config', 'commit.gpgsign', 'false')
    [IO.File]::WriteAllText((Join-Path $repo '.gitattributes'), "*.md text`n")
    $null = Invoke-TestGit @('add', '--', '.gitattributes')
    $null = Invoke-TestGit @('commit', '-m', 'Initial test attributes')
    $null = Invoke-TestGit @('remote', 'add', 'origin', $remote)
    $null = Invoke-TestGit @('push', '-u', 'origin', 'main')
    $checkpoint = & (Join-Path $CheckpointScriptsPath 'New-Checkpoint.ps1') -StorageRoot $repo -Path $repo -SessionId ([guid]::NewGuid().ToString())
    $text = [regex]::Replace([IO.File]::ReadAllText($checkpoint.Path), '(?m)^(## [^\r\n]+)', '$1' + "`r`n`r`nNone.")
    [IO.File]::WriteAllText($checkpoint.Path, $text, (New-Object Text.UTF8Encoding $false))
    $relative = Join-Path $checkpoint.ProjectName (Split-Path -Leaf $checkpoint.Path)
    $syncArguments = @{ StorageRoot = $repo; RelativePath = $relative; CheckpointScriptsPath = $CheckpointScriptsPath }
    $result = & $wrapper @syncArguments
    Assert-Test ($result.Synced -and $result.Commit -eq ((Invoke-TestGit @('rev-parse', 'origin/main')) -join '')) 'commits and verifies local remote'
    $committedFiles = @(Invoke-TestGit @('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'))
    Assert-Test ($committedFiles.Count -eq 1 -and $committedFiles[0] -eq $relative.Replace('\', '/')) 'commits only selected checkpoint'
    $message = (Invoke-TestGit @('log', '-1', '--format=%B')) -join "`n"
    Assert-Test ($message.Contains('Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>')) 'adds co-author trailer'

    [IO.File]::WriteAllText((Join-Path $repo 'unrelated.txt'), 'Keep this file.')
    $again = & $wrapper @syncArguments
    Assert-Test ($again.Synced -and $again.Commit -eq $result.Commit) 'idempotent sync creates no extra commit'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $repo 'unrelated.txt')) -eq 'Keep this file.') 'preserves unrelated untracked work'

    $nestedStore = Join-Path $repo 'nested\checkpoints'
    $nestedCheckpoint = & (Join-Path $CheckpointScriptsPath 'New-Checkpoint.ps1') -StorageRoot $nestedStore -Path $repo -SessionId ([guid]::NewGuid().ToString())
    $nestedText = [regex]::Replace([IO.File]::ReadAllText($nestedCheckpoint.Path), '(?m)^(## [^\r\n]+)', '$1' + "`r`n`r`nNone.")
    [IO.File]::WriteAllText($nestedCheckpoint.Path, $nestedText, (New-Object Text.UTF8Encoding $false))
    $nestedRelative = Join-Path $nestedCheckpoint.ProjectName (Split-Path -Leaf $nestedCheckpoint.Path)
    $nestedResult = & $wrapper -StorageRoot $nestedStore -RelativePath $nestedRelative -CheckpointScriptsPath $CheckpointScriptsPath
    Assert-Test ($nestedResult.Synced -and $nestedResult.RepositoryRoot -eq $repo -and $nestedResult.StorageRoot -eq $nestedStore) 'derives repository root from nested storage'
    $nestedCommittedFiles = @(Invoke-TestGit @('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'))
    Assert-Test ($nestedCommittedFiles.Count -eq 1 -and $nestedCommittedFiles[0] -eq ('nested/checkpoints/' + $nestedRelative.Replace('\', '/'))) 'maps storage-relative selection to repository-relative commit'

    $null = Invoke-TestGit @('add', '--', 'unrelated.txt')
    Assert-Rejected { & $wrapper @syncArguments } 'refuses unrelated staged file'
    Assert-Test (((Invoke-TestGit @('diff', '--cached', '--name-only')) -join '') -eq 'unrelated.txt') 'leaves unrelated staged work unchanged'
    $null = Invoke-TestGit @('commit', '-m', 'Unrelated local change')
    Assert-Rejected { & $wrapper @syncArguments } 'refuses to push unrelated pending commit'
    $null = Invoke-TestGit @('push', 'origin', 'main')

    Assert-Rejected { & $wrapper -StorageRoot $repo -RelativePath '../escape.md' -CheckpointScriptsPath $CheckpointScriptsPath } 'refuses traversal'
    Assert-Rejected { & $wrapper -StorageRoot $remote -RelativePath $relative -CheckpointScriptsPath $CheckpointScriptsPath } 'refuses storage without a Git working tree'
    [IO.File]::WriteAllText($checkpoint.Path, 'Not a valid checkpoint.')
    Assert-Rejected { & $wrapper @syncArguments } 'refuses invalid checkpoint content'
    [IO.File]::WriteAllText($checkpoint.Path, $text + "`r`nUpdated test detail.`r`n", (New-Object Text.UTF8Encoding $false))

    $null = Invoke-TestGit @('remote', 'set-url', '--push', 'origin', (Join-Path $testRoot 'missing.git'))
    Assert-Rejected { & $wrapper @syncArguments } 'reports failed push instead of claiming sync'
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $repo '.git/checkpoint-sync.lock'))) 'releases sync lock after failure'
    $beforeRetry = (Invoke-TestGit @('rev-parse', 'HEAD')) -join ''
    $null = Invoke-TestGit @('remote', 'set-url', '--push', 'origin', $remote)
    $retried = & $wrapper @syncArguments
    Assert-Test ($retried.Synced -and $retried.Commit -eq $beforeRetry) 'retries checkpoint-only pending commit without duplicate commit'

    $lockPath = Join-Path $repo '.git/checkpoint-sync.lock'
    [IO.File]::WriteAllText($lockPath, "$PID`nheld by test")
    $releaseJob = Start-Job -ScriptBlock {
        param ($Path)
        Start-Sleep -Milliseconds 750
        Remove-Item -LiteralPath $Path -Force
    } -ArgumentList $lockPath
    try
    {
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $waited = & $wrapper @syncArguments -LockTimeoutSeconds 5
        $stopwatch.Stop()
        Assert-Test ($waited.Synced -and $stopwatch.ElapsedMilliseconds -ge 500) 'waits for another checkpoint writer in this checkout'
    }
    finally
    {
        $null = Wait-Job -Job $releaseJob
        Remove-Job -Job $releaseJob
        if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force }
    }

    $peer = Join-Path $testRoot 'peer'
    $null = & git clone --branch main $remote $peer
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create peer test clone.' }
    $null = & git -C $peer config user.name 'Checkpoint tests'
    $null = & git -C $peer config user.email 'checkpoint-tests@example.invalid'
    $null = & git -C $peer config commit.gpgsign false

    $peerProject = Join-Path $peer 'peer-project'
    New-Item -ItemType Directory -Path $peerProject -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $peerProject 'checkpoint-2026-11-23T1300.md'),
        'Peer checkpoint written before the local push.'
    )
    $null = & git -C $peer add -- peer-project/checkpoint-2026-11-23T1300.md
    $null = & git -C $peer commit -m 'Peer checkpoint'
    $localCheckpointText = [IO.File]::ReadAllText($checkpoint.Path)
    [IO.File]::WriteAllText(
        $checkpoint.Path,
        $localCheckpointText + "`r`nLocal checkpoint update before the competing push.`r`n",
        (New-Object Text.UTF8Encoding $false)
    )
    $hook = Join-Path $repo '.git/hooks/pre-push'
    [IO.File]::WriteAllText(
        $hook,
        "#!/bin/sh`ngit -C `"$($peer.Replace('\', '/'))`" push origin main`nexit 0`n"
    )
    $raced = & $wrapper @syncArguments
    Remove-Item -LiteralPath $hook -Force
    Assert-Test ($raced.Synced -and $raced.PushRetries -eq 1 -and $raced.Rebased) 'retries one disjoint checkpoint push race with a safe rebase'
    Assert-Test (((Invoke-TestGit @('rev-parse', 'HEAD')) -join '') -eq $raced.Commit) 'push race retry leaves local and remote synchronized'
    $peerCommit = ((& git -C $peer rev-parse HEAD) -join '').Trim()
    Assert-Test ($peerCommit -in @(Invoke-TestGit @('rev-list', 'HEAD'))) 'push race retry preserves the peer checkpoint commit'
    $null = & git -C $peer fetch origin main
    $null = & git -C $peer merge --ff-only origin/main

    [IO.File]::WriteAllText(
        (Join-Path $peerProject 'checkpoint-2026-11-23T1301.md'),
        'A second peer checkpoint that requires a fast-forward.'
    )
    $null = & git -C $peer add -- peer-project/checkpoint-2026-11-23T1301.md
    $null = & git -C $peer commit -m 'Second peer checkpoint'
    $null = & git -C $peer push origin main
    $fastForwarded = & $wrapper @syncArguments
    Assert-Test (
        $fastForwarded.Synced -and
        $fastForwarded.FastForwarded -and
        -not $fastForwarded.Rebased -and
        $fastForwarded.PushRetries -eq 0
    ) 'fast-forwards a remote-ahead branch after disjoint checkpoint commits'

    $null = & git -C $peer switch -c peer-merge
    [IO.File]::WriteAllText(
        (Join-Path $peerProject 'checkpoint-2026-11-23T1302.md'),
        'Checkpoint on a branch that will be merged.'
    )
    $null = & git -C $peer add -- peer-project/checkpoint-2026-11-23T1302.md
    $null = & git -C $peer commit -m 'Branch checkpoint'
    $null = & git -C $peer switch main
    $null = & git -C $peer merge --no-ff peer-merge -m 'Merge peer checkpoint'
    $null = & git -C $peer push origin main
    $beforeRemoteMerge = (Invoke-TestGit @('rev-parse', 'HEAD')) -join ''
    Assert-Rejected { & $wrapper @syncArguments } 'refuses a remote checkpoint merge commit'
    Assert-Test (((Invoke-TestGit @('rev-parse', 'HEAD')) -join '') -eq $beforeRemoteMerge) 'remote merge refusal preserves local branch'
    $null = Invoke-TestGit @('merge', '--ff-only', 'origin/main')

    $peerRelative = Join-Path $checkpoint.ProjectName (Split-Path -Leaf $checkpoint.Path)
    $peerSelected = Join-Path $peer $peerRelative
    [IO.File]::WriteAllText($peerSelected, ([IO.File]::ReadAllText($peerSelected) + "`r`nPeer selected-file change.`r`n"))
    $null = & git -C $peer add -- $peerRelative.Replace('\', '/')
    $null = & git -C $peer commit -m 'Change selected peer checkpoint'
    $null = & git -C $peer push origin main
    $beforeSamePath = (Invoke-TestGit @('rev-parse', 'HEAD')) -join ''
    Assert-Rejected { & $wrapper @syncArguments } 'refuses a remote update to the selected checkpoint path'
    Assert-Test (((Invoke-TestGit @('rev-parse', 'HEAD')) -join '') -eq $beforeSamePath) 'same-path refusal preserves local branch'
    $null = Invoke-TestGit @('merge', '--ff-only', 'origin/main')

    [IO.File]::WriteAllText((Join-Path $peer 'peer.txt'), 'Remote change.')
    $null = & git -C $peer add -- peer.txt
    $null = & git -C $peer commit -m 'Peer change'
    $null = & git -C $peer push origin main
    if ($LASTEXITCODE -ne 0) { throw 'Cannot advance test remote.' }
    $before = (Invoke-TestGit @('rev-parse', 'HEAD')) -join ''
    Assert-Rejected { & $wrapper @syncArguments } 'refuses remote-ahead branch with an unrelated file'
    Assert-Test (((Invoke-TestGit @('rev-parse', 'HEAD')) -join '') -eq $before) 'preserves local branch on divergence'
    Write-Host "$passed tests passed."
}
finally
{
    if (Test-Path -LiteralPath $testRoot)
    {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
