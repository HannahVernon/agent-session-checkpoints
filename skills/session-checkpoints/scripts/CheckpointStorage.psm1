<#
.SYNOPSIS
    Validates explicit checkpoint roots and relative targets.
#>
Set-StrictMode -Version Latest

function Resolve-CheckpointStoragePath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StorageRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RelativePath,

        [switch] $AllowMissing
    )

    $ErrorActionPreference = 'Stop'
    $rootInput = $StorageRoot

    if ($rootInput -eq '~')
    {
        $rootInput = $HOME
    }
    elseif ($rootInput -match '^~[\\/]')
    {
        $rootInput = Join-Path $HOME $rootInput.Substring(2)
    }

    $isWindows = [IO.Path]::DirectorySeparatorChar -eq '\'

    if (-not [IO.Path]::IsPathRooted($rootInput) -or
        ($isWindows -and $rootInput -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') -or
        $rootInput -match '[\x00-\x1f*?"<>|]' -or
        ($rootInput -replace '^[a-zA-Z]:', '') -match ':')
    {
        throw 'StorageRoot must be an absolute filesystem path or a path beginning with ~.'
    }

    $root = [IO.Path]::GetFullPath($rootInput)
    $root = $root.TrimEnd([char[]] @('\', '/'))

    if ($root -eq '')
    {
        $root = [IO.Path]::DirectorySeparatorChar.ToString()
    }
    elseif ($isWindows -and $root -match '^[a-zA-Z]:$')
    {
        $root += '\'
    }

    if ($RelativePath -ne '.')
    {
        if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '^[\\/]')
        {
            throw 'RelativePath must be relative to StorageRoot.'
        }

        foreach ($part in ($RelativePath -split '[\\/]'))
        {
            if ([string]::IsNullOrWhiteSpace($part) -or $part -in @('.', '..') -or
                $part -match '[\x00-\x1f:*?"<>|]' -or $part -match '[. ]$' -or
                $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)')
            {
                throw "Unsafe relative path component: '$part'."
            }
        }
    }

    $separator = [IO.Path]::DirectorySeparatorChar
    $relative = $RelativePath.Replace('\', $separator).Replace('/', $separator)
    $target = if ($relative -eq '.') { $root } else { [IO.Path]::GetFullPath((Join-Path $root $relative)) }
    $comparison = if ($isWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $prefix = $root.TrimEnd([char[]] @('\', '/')) + $separator

    if (-not $target.Equals($root, $comparison) -and -not $target.StartsWith($prefix, $comparison))
    {
        throw 'RelativePath escapes StorageRoot.'
    }

    $current = $target
    $targetExists = $false
    $rootExists = $false

    while ($current)
    {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue

        if ($item)
        {
            $linkType = $item.PSObject.Properties['LinkType']
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($linkType -and -not [string]::IsNullOrEmpty([string] $linkType.Value)))
            {
                throw "Linked paths are not permitted: $current"
            }

            if ($current.Equals($target, $comparison)) { $targetExists = $true }
            if ($current.Equals($root, $comparison)) { $rootExists = $true }

            if (-not $current.Equals($target, $comparison) -and -not $item.PSIsContainer)
            {
                throw "Parent path is not a directory: $current"
            }

            if ($current.Equals($root, $comparison) -and -not $item.PSIsContainer)
            {
                throw "StorageRoot is not a directory: $root"
            }
        }

        $parent = [IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current = $parent
    }

    if (-not $AllowMissing -and (-not $rootExists -or -not $targetExists))
    {
        throw "Checkpoint path does not exist: $target"
    }

    [pscustomobject] @{
        StorageRoot = $root
        Path        = $target
        Exists      = $targetExists
    }
}

function Get-CheckpointStorageFiles
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $StorageRoot,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [switch] $Recurse
    )

    $ErrorActionPreference = 'Stop'
    $target = Resolve-CheckpointStoragePath -StorageRoot $StorageRoot -RelativePath $RelativePath
    $item = Get-Item -LiteralPath $target.Path -Force

    if (-not $item.PSIsContainer)
    {
        $item
        return
    }

    $folders = New-Object 'System.Collections.Generic.Queue[string]'
    $folders.Enqueue($target.Path)

    while ($folders.Count -gt 0)
    {
        $folder = $folders.Dequeue()

        foreach ($entry in @(Get-ChildItem -LiteralPath $folder -Force))
        {
            if ($entry.Name -in @('.git', '.hg', '.svn')) { continue }
            $childPath = $entry.FullName.Substring($target.StorageRoot.TrimEnd('\', '/').Length + 1)
            $null = Resolve-CheckpointStoragePath -StorageRoot $target.StorageRoot -RelativePath $childPath

            if ($entry.PSIsContainer)
            {
                if ($Recurse) { $folders.Enqueue($entry.FullName) }
            }
            elseif ($entry.Name -like 'checkpoint-*.md')
            {
                $entry
            }
        }
    }
}

Export-ModuleMember -Function Resolve-CheckpointStoragePath, Get-CheckpointStorageFiles
