<#
.SYNOPSIS
    Validates, commits and verifies explicitly selected checkpoint files.
.DESCRIPTION
    Requires a configured Git upstream.  Refuses unrelated staged changes,
    pending unrelated commits and same-file conflicts.  Serializes writers in
    the same checkout and safely incorporates disjoint checkpoint commits from
    other writers.  Derives the Git root from StorageRoot.
    Never force-pushes, deletes branches or edits checkpoint text.
.PARAMETER StorageRoot
    Explicit canonical checkpoint storage root in a Git working tree.
    No fallback is used; Git identifies the containing repository.
.PARAMETER RelativePath
    Existing checkpoint filenames or index.md files relative to StorageRoot.
.PARAMETER CheckpointScriptsPath
    Directory containing the checkpoint skill's scripts and storage module.
.PARAMETER Message
    Commit subject.  The script adds the Copilot co-author trailer.
.PARAMETER LockTimeoutSeconds
    Maximum time to wait for another checkpoint writer in this checkout.
.EXAMPLE
    ./Sync-Checkpoint.ps1 -StorageRoot ~/agent-session-state -RelativePath invoice-api/checkpoint-2026-03-14T1610.md -CheckpointScriptsPath ./skills/session-checkpoints/scripts
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $StorageRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]] $RelativePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $CheckpointScriptsPath,

    [string] $Message = 'Save session checkpoint',

    [Parameter()]
    [ValidateRange(1, 300)]
    [int] $LockTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$oldTerminalPrompt = $env:GIT_TERMINAL_PROMPT
$env:GIT_TERMINAL_PROMPT = '0'
$oldLiteralPathspecs = $env:GIT_LITERAL_PATHSPECS
$lockStream = $null
$lockPath = $null

function Invoke-CheckpointGit
{
    param ([string[]] $GitArguments)
    $output = @(& git --no-pager -c core.quotepath=false -C $script:RepositoryRoot @GitArguments)
    if ($LASTEXITCODE -ne 0)
    {
        throw "Git failed ($LASTEXITCODE): $($GitArguments[0]). No automatic recovery was attempted."
    }
    $output
}

function Assert-CheckpointIndex
{
    $staged = @(Invoke-CheckpointGit @('diff', '--cached', '--name-only'))
    $unrelated = @($staged | Where-Object { $_ -cnotin $script:repoPaths })
    if ($unrelated.Count -gt 0)
    {
        throw "Unrelated files are staged. Leave them unchanged and commit them separately: $($unrelated -join ', ')"
    }
}

function Get-CheckpointLock
{
    param (
        [string] $Path,
        [int] $TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($true)
    {
        try
        {
            $stream = [IO.File]::Open(
                $Path,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            $content = [Text.Encoding]::UTF8.GetBytes("$PID`n" + (Get-Date -Format 'o'))
            $stream.Write($content, 0, $content.Length)
            $stream.Flush()
            return $stream
        }
        catch [IOException]
        {
            $ownerExists = $true

            if (Test-Path -LiteralPath $Path -PathType Leaf)
            {
                $ownerPid = 0
                $firstLine = @(Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction SilentlyContinue) |
                             Select-Object -First 1

                if ($firstLine -and [int]::TryParse([string] $firstLine, [ref] $ownerPid))
                {
                    $ownerExists = $null -ne (Get-Process -Id $ownerPid -ErrorAction SilentlyContinue)
                }

                if (-not $ownerExists -and
                    ((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds -ge 5)
                {
                    Remove-Item -LiteralPath $Path -Force
                    continue
                }
            }

            if ((Get-Date) -ge $deadline)
            {
                throw "Another checkpoint sync holds $Path. Wait for it to finish, then retry."
            }

            Start-Sleep -Milliseconds 100
        }
    }
}

function Test-CheckpointRepositoryPath
{
    param ([string] $Path)

    return $Path -match '(^|/)(checkpoint-\d{4}-\d{2}-\d{2}T\d{4}(?:-\d+)?|index)\.md$'
}

function Get-CheckpointCommitPaths
{
    param ([string[]] $Commits)

    $paths = New-Object System.Collections.ArrayList

    foreach ($commit in $Commits)
    {
        foreach ($path in @(Invoke-CheckpointGit @('diff-tree', '--root', '--no-commit-id', '--name-only', '-r', '-m', $commit)))
        {
            if ($path -and $path -notin $paths)
            {
                $null = $paths.Add($path)
            }
        }
    }

    $paths
}

function Assert-CheckpointOnlyCommits
{
    param (
        [string[]] $Commits,
        [string[]] $AllowedPaths
    )

    foreach ($commit in $Commits)
    {
        $parents = @(((Invoke-CheckpointGit @('rev-list', '--parents', '-n', '1', $commit)) -join '') -split ' ')

        if ($parents.Count -gt 2)
        {
            throw 'An unpushed merge requires manual review before syncing.'
        }
    }

    $changed = @(Get-CheckpointCommitPaths -Commits $Commits)
    $unrelated = @($changed | Where-Object { $_ -notin $AllowedPaths })

    if ($unrelated.Count -gt 0)
    {
        throw "Pending commits contain files outside the selected checkpoints: $($unrelated -join ', ')."
    }

    $changed
}

function Assert-RemoteCheckpointCommits
{
    param ([string[]] $Commits)

    foreach ($commit in $Commits)
    {
        $parents = @(((Invoke-CheckpointGit @('rev-list', '--parents', '-n', '1', $commit)) -join '') -split ' ')

        if ($parents.Count -gt 2)
        {
            throw 'A remote merge requires manual review before syncing.'
        }
    }

    $changed = @(Get-CheckpointCommitPaths -Commits $Commits)
    $unrelated = @($changed | Where-Object { -not (Test-CheckpointRepositoryPath -Path $_) })

    if ($unrelated.Count -gt 0)
    {
        throw "Remote commits contain files outside the checkpoint store format: $($unrelated -join ', ')."
    }

    $changed
}

function Assert-NoPathOverlap
{
    param (
        [string[]] $First,
        [string[]] $Second,
        [string] $Reason
    )

    $overlap = @($First | Where-Object { $_ -in $Second })

    if ($overlap.Count -gt 0)
    {
        throw "$Reason`: $($overlap -join ', ')."
    }
}

function Sync-CheckpointUpstream
{
    $upstreamInHead = $false
    $null = & git --no-pager -c core.quotepath=false -C $script:RepositoryRoot merge-base --is-ancestor '@{upstream}' HEAD 2>$null
    $upstreamInHead = $LASTEXITCODE -eq 0
    $headInUpstream = $false
    $null = & git --no-pager -c core.quotepath=false -C $script:RepositoryRoot merge-base --is-ancestor HEAD '@{upstream}' 2>$null
    $headInUpstream = $LASTEXITCODE -eq 0

    if ($upstreamInHead)
    {
        $pending = @(Invoke-CheckpointGit @('rev-list', '@{upstream}..HEAD'))
        $null = Assert-CheckpointOnlyCommits -Commits $pending -AllowedPaths $script:repoPaths

        return [pscustomobject] @{
            Changed          = $false
            FastForwarded    = $false
            Rebased          = $false
            PreviousUpstream = (Invoke-CheckpointGit @('rev-parse', '@{upstream}')) -join ''
        }
    }

    $previousUpstream = (Invoke-CheckpointGit @('rev-parse', '@{upstream}')) -join ''
    $mergeBase = (Invoke-CheckpointGit @('merge-base', 'HEAD', '@{upstream}')) -join ''
    $remoteCommits = @(Invoke-CheckpointGit @('rev-list', "$mergeBase..@{upstream}"))
    $remotePaths = @(Assert-RemoteCheckpointCommits -Commits $remoteCommits)

    Assert-NoPathOverlap -First $remotePaths -Second $script:repoPaths `
        -Reason 'A remote writer changed the selected checkpoint path'

    if ($headInUpstream)
    {
        $dirtyTracked = @(Invoke-CheckpointGit @('diff', '--name-only', 'HEAD'))
        Assert-NoPathOverlap -First $remotePaths -Second $dirtyTracked `
            -Reason 'A remote writer changed a locally modified tracked path'
        $null = Invoke-CheckpointGit @('merge', '--ff-only', '@{upstream}')

        return [pscustomobject] @{
            Changed          = $true
            FastForwarded    = $true
            Rebased          = $false
            PreviousUpstream = $previousUpstream
        }
    }

    $localCommits = @(Invoke-CheckpointGit @('rev-list', "$mergeBase..HEAD"))
    $localPaths = @(Assert-CheckpointOnlyCommits -Commits $localCommits -AllowedPaths $script:repoPaths)
    Assert-NoPathOverlap -First $localPaths -Second $remotePaths `
        -Reason 'Remote and local checkpoint commits changed the same path'

    $dirtyTracked = @((@(
        @(Invoke-CheckpointGit @('diff', '--name-only', 'HEAD')) +
        @(Invoke-CheckpointGit @('diff', '--cached', '--name-only'))
    )) | Select-Object -Unique)

    if ($dirtyTracked.Count -gt 0)
    {
        throw "Cannot rebase checkpoint-only commits while tracked worktree changes exist: $($dirtyTracked -join ', ')."
    }

    $currentBranch = (Invoke-CheckpointGit @('symbolic-ref', '--quiet', '--short', 'HEAD')) -join ''
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try
    {
        $rebaseOutput = @(& git --no-pager -c core.quotepath=false -C $script:RepositoryRoot rebase --onto '@{upstream}' $mergeBase $currentBranch 2>&1)
        $rebaseExitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    if ($rebaseExitCode -ne 0)
    {
        $null = & git --no-pager -c core.quotepath=false -C $script:RepositoryRoot rebase --abort 2>$null
        throw "Checkpoint-only rebase failed and was aborted: $($rebaseOutput -join ' ')"
    }

    [pscustomobject] @{
        Changed          = $true
        FastForwarded    = $false
        Rebased          = $true
        PreviousUpstream = $previousUpstream
    }
}

function Invoke-CheckpointPush
{
    param ([string] $Remote, [string] $RemoteRef)

    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try
    {
        $output = @(& git --no-pager -c core.quotepath=false -C $script:RepositoryRoot push $Remote "HEAD:$RemoteRef" 2>&1)
        $pushExitCode = $LASTEXITCODE
    }
    finally
    {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    [pscustomobject] @{
        Success = $pushExitCode -eq 0
        Output  = ($output -join ' ')
    }
}

try
{
    foreach ($override in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE'))
    {
        if ([Environment]::GetEnvironmentVariable($override))
        {
            throw "Unset the Git path override before syncing checkpoints: $override"
        }
    }

    $env:GIT_LITERAL_PATHSPECS = '1'
    $modulePath = Join-Path $CheckpointScriptsPath 'CheckpointStorage.psm1'
    Import-Module $modulePath -Force
    $store = Resolve-CheckpointStoragePath -StorageRoot $StorageRoot -RelativePath '.'
    $StorageRoot = $store.Path
    $top = @(& git --no-pager -c core.quotepath=false -C $StorageRoot rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0)
    {
        throw 'StorageRoot must belong to a Git working tree.'
    }
    $RepositoryRoot = (Resolve-CheckpointStoragePath -StorageRoot ($top -join '') -RelativePath '.').Path
    $comparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $repoPrefix = $RepositoryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar

    if (-not $StorageRoot.Equals($RepositoryRoot, $comparison) -and -not $StorageRoot.StartsWith($repoPrefix, $comparison))
    {
        throw 'StorageRoot must belong to RepositoryRoot.'
    }

    foreach ($operation in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer'))
    {
        $operationPath = (Invoke-CheckpointGit @('rev-parse', '--git-path', $operation)) -join ''
        if (-not [IO.Path]::IsPathRooted($operationPath)) { $operationPath = Join-Path $RepositoryRoot $operationPath }
        if (Test-Path -LiteralPath $operationPath) { throw "Git operation in progress: $operation" }
    }

    $branch = (Invoke-CheckpointGit @('symbolic-ref', '--quiet', '--short', 'HEAD')) -join ''
    $remote = (Invoke-CheckpointGit @('for-each-ref', '--format=%(upstream:remotename)', "refs/heads/$branch")) -join ''
    $remoteRef = (Invoke-CheckpointGit @('for-each-ref', '--format=%(upstream:remoteref)', "refs/heads/$branch")) -join ''
    if (-not $remote -or $remote -eq '.' -or $remote.StartsWith('-') -or $remoteRef -notmatch '^refs/heads/')
    {
        throw 'Configure a remote branch upstream before syncing checkpoints.'
    }

    $gitDir = (Invoke-CheckpointGit @('rev-parse', '--absolute-git-dir')) -join ''
    $lockPath = Join-Path $gitDir 'checkpoint-sync.lock'
    $lockStream = Get-CheckpointLock -Path $lockPath -TimeoutSeconds $LockTimeoutSeconds

    $repoPaths = @()
    $targetPaths = @{}

    foreach ($relative in $RelativePath)
    {
        $target = Resolve-CheckpointStoragePath -StorageRoot $StorageRoot -RelativePath $relative
        $leaf = Split-Path -Leaf $target.Path
        if (-not (Test-Path -LiteralPath $target.Path -PathType Leaf) -or
            $leaf -notmatch '^(?:checkpoint-\d{4}-\d{2}-\d{2}T\d{4}(?:-\d+)?|index)\.md$')
        {
            throw "Select a checkpoint file or index.md, not a directory or another file: $relative"
        }

        $repoPath = $target.Path.Substring($repoPrefix.Length).Replace('\', '/')
        if ($repoPath -cnotin $repoPaths) { $repoPaths += $repoPath }
        $targetPaths[$repoPath] = $target.Path
    }

    Assert-CheckpointIndex
    $null = Invoke-CheckpointGit @('fetch', '--no-tags', $remote, $remoteRef)
    $upstreamSync = Sync-CheckpointUpstream

    $expectedHashes = @{}

    foreach ($repoPath in $repoPaths)
    {
        $targetPath = $targetPaths[$repoPath]
        $leaf = Split-Path -Leaf $targetPath

        if ($leaf -ne 'index.md')
        {
            $relative = $repoPath

            if (-not $StorageRoot.Equals($RepositoryRoot, $comparison))
            {
                $storagePrefix = $StorageRoot.Substring($RepositoryRoot.Length).TrimStart('\', '/').Replace('\', '/')
                $relative = $repoPath.Substring($storagePrefix.Length).TrimStart('/')
            }

            $findings = @(& (Join-Path $CheckpointScriptsPath 'Test-Checkpoint.ps1') -StorageRoot $StorageRoot -RelativePath $relative -Quiet)
            if (@($findings | Where-Object { $_.Severity -in @('High', 'Medium') }).Count -gt 0)
            {
                throw "Checkpoint validation failed for $repoPath`: $($findings.Detail -join ' ')"
            }
            foreach ($finding in $findings) { Write-Warning $finding.Detail }
        }

        $expectedHashes[$repoPath] = (Invoke-CheckpointGit @('hash-object', "--path=$repoPath", '--', $targetPath)) -join ''
    }

    $null = Invoke-CheckpointGit (@('add', '--') + $repoPaths)
    Assert-CheckpointIndex
    $null = Invoke-CheckpointGit (@('diff', '--cached', '--check', '--') + $repoPaths)
    $selectedChanges = @(Invoke-CheckpointGit (@('diff', '--cached', '--name-only', '--') + $repoPaths))

    if ($selectedChanges.Count -gt 0)
    {
        $null = Invoke-CheckpointGit (@('commit', '--only', '-m', $Message, '-m', 'Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>', '--') + $repoPaths)
    }

    $commitId = (Invoke-CheckpointGit @('rev-parse', 'HEAD')) -join ''
    foreach ($repoPath in $repoPaths)
    {
        $actual = (Invoke-CheckpointGit @('rev-parse', "${commitId}:$repoPath")) -join ''
        if ($actual -ne $expectedHashes[$repoPath]) { throw "Committed contents differ from the validated file: $repoPath" }
    }

    $push = Invoke-CheckpointPush -Remote $remote -RemoteRef $remoteRef
    $pushRetries = 0

    if (-not $push.Success)
    {
        $remoteAtPushAttempt = (Invoke-CheckpointGit @('rev-parse', '@{upstream}')) -join ''
        $null = Invoke-CheckpointGit @('fetch', '--no-tags', $remote, $remoteRef)
        $currentRemote = (Invoke-CheckpointGit @('rev-parse', '@{upstream}')) -join ''

        if ($currentRemote -eq $remoteAtPushAttempt)
        {
            throw "Git push failed; the local checkpoint commit remains available for retry: $($push.Output)"
        }

        $retrySync = Sync-CheckpointUpstream
        $pushRetries = 1
        $upstreamSync.Rebased = $upstreamSync.Rebased -or $retrySync.Rebased
        $upstreamSync.FastForwarded = $upstreamSync.FastForwarded -or $retrySync.FastForwarded
        $upstreamSync.Changed = $upstreamSync.Changed -or $retrySync.Changed
        $commitId = (Invoke-CheckpointGit @('rev-parse', 'HEAD')) -join ''

        foreach ($repoPath in $repoPaths)
        {
            $actual = (Invoke-CheckpointGit @('rev-parse', "${commitId}:$repoPath")) -join ''
            if ($actual -ne $expectedHashes[$repoPath])
            {
                throw "Committed contents differ from the validated file after checkpoint retry: $repoPath"
            }
        }

        $push = Invoke-CheckpointPush -Remote $remote -RemoteRef $remoteRef

        if (-not $push.Success)
        {
            throw "Git push failed again after one checkpoint-only retry; the local commit remains available: $($push.Output)"
        }
    }

    $remoteResult = (Invoke-CheckpointGit @('ls-remote', '--exit-code', $remote, $remoteRef)) -join ''
    if (($remoteResult -split '\s+')[0] -ne $commitId) { throw 'Remote verification failed; do not report the checkpoint synced.' }

    [pscustomobject] @{
        RepositoryRoot = $RepositoryRoot
        StorageRoot    = $StorageRoot
        Files          = $repoPaths
        Commit         = $commitId
        Remote         = $remote
        RemoteRef      = $remoteRef
        FastForwarded  = $upstreamSync.FastForwarded
        Rebased        = $upstreamSync.Rebased
        PushRetries    = $pushRetries
        Synced         = $true
    }
}
finally
{
    $env:GIT_TERMINAL_PROMPT = $oldTerminalPrompt
    $env:GIT_LITERAL_PATHSPECS = $oldLiteralPathspecs
    if ($lockStream)
    {
        $lockStream.Dispose()
        Remove-Item -LiteralPath $lockPath -Force
    }
}
