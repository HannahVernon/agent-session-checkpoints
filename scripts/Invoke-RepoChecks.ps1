<#
.SYNOPSIS
    Validates this repository before a commit.

.DESCRIPTION
    Runs the checks the AGENT-README commits to:

      Parse       every .ps1 parses with the PowerShell parser
      Help        every .ps1 has comment-based help with a .SYNOPSIS
      Dashes      no em-dashes, en-dashes, or hyphen lookalikes in any text file
      Manifests   plugin.json and .claude-plugin/plugin.json agree on name,
                  version, description and license
      Leaks       no internal identifiers, absolute local paths, or private
                  host names in any tracked text file

    The leak check exists because this repository is public.  It is a
    heuristic, not a guarantee; read the diff before publishing.

.PARAMETER Path
    Repository root.  Defaults to the parent of this script's directory.

.PARAMETER SkipLeakCheck
    Skip the internal-identifier scan.

.EXAMPLE
    .\scripts\Invoke-RepoChecks.ps1
    Runs every check and returns a non-zero exit code on failure.

.OUTPUTS
    One PSCustomObject per finding, with Check, File and Detail.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string] $Path = (Split-Path -Parent $PSScriptRoot),

    [Parameter()]
    [switch] $SkipLeakCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$findings = New-Object System.Collections.ArrayList

function Add-Finding
{
    param ([string] $Check, [string] $File, [string] $Detail)

    $null = $findings.Add([pscustomobject] @{
        Check  = $Check
        File   = $File
        Detail = $Detail
    })
}

$scripts = @(Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -File -Recurse |
             Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })

foreach ($script in $scripts)
{
    $rel       = $script.FullName.Substring($Path.Length).TrimStart('\', '/')
    $parseErrs = $null
    $tokens    = $null

    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref] $tokens, [ref] $parseErrs) | Out-Null

    if ($parseErrs -and $parseErrs.Count -gt 0)
    {
        foreach ($parseErr in $parseErrs)
        {
            Add-Finding -Check 'Parse' -File $rel -Detail "Line $($parseErr.Extent.StartLineNumber): $($parseErr.Message)"
        }
    }

    $text = [IO.File]::ReadAllText($script.FullName)

    if ($text -notmatch '(?s)<#.*?\.SYNOPSIS.*?#>')
    {
        Add-Finding -Check 'Help' -File $rel -Detail 'No comment-based help block containing .SYNOPSIS.'
    }

    if ($text -notmatch '\[CmdletBinding\(\)\]')
    {
        Add-Finding -Check 'Help' -File $rel -Detail 'No [CmdletBinding()] attribute.'
    }
}

$textFiles = @(Get-ChildItem -LiteralPath $Path -File -Recurse |
               Where-Object {
                   $_.FullName -notmatch '[\\/]\.git[\\/]' -and
                   $_.Extension -in @('.md', '.ps1', '.json', '.txt', '.yml', '.yaml', '.gitattributes', '')
               })

$dashMap = @{
    "$([char]0x2014)" = 'em-dash'
    "$([char]0x2013)" = 'en-dash'
    "$([char]0x2012)" = 'figure dash'
    "$([char]0x2015)" = 'horizontal bar'
    "$([char]0x2010)" = 'hyphen U+2010'
    "$([char]0x2011)" = 'non-breaking hyphen'
    "$([char]0x00AD)" = 'soft hyphen'
    "$([char]0x2212)" = 'minus sign'
    "$([char]0xFF0D)" = 'fullwidth hyphen-minus'
}

$leakPatterns = @(
    @{ Name = 'Local path';    Pattern = '(?i)[a-z]:\\(dev|temp|users)\\' },
    @{ Name = 'User profile';  Pattern = '(?i)\\Users\\[a-z0-9_]+\\' },
    @{ Name = 'Admin account'; Pattern = '(?i)\badm_[a-z0-9]+\b' },
    @{ Name = 'Private host';  Pattern = '(?i)\b[a-z0-9-]+\.(corp|internal|local|lan)\b' },
    @{ Name = 'Windows host';  Pattern = '\b[A-Z]{2,4}\d{5,}\b' },
    @{ Name = 'IPv4 literal';  Pattern = '\b(?!0\.0\.0\.0|127\.0\.0\.1|255\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' },
    @{ Name = 'Secret-ish';    Pattern = '(?i)\b(password|pwd|apikey|api_key|secret|token)\s*[:=]\s*["\x27]?[A-Za-z0-9+/_-]{12,}' }
)

foreach ($file in $textFiles)
{
    $rel  = $file.FullName.Substring($Path.Length).TrimStart('\', '/')
    $text = [IO.File]::ReadAllText($file.FullName)

    foreach ($dash in $dashMap.Keys)
    {
        $count = ([regex]::Matches($text, [regex]::Escape($dash))).Count

        if ($count -gt 0)
        {
            Add-Finding -Check 'Dashes' -File $rel -Detail "$count occurrence(s) of $($dashMap[$dash]).  Use a plain hyphen."
        }
    }

    if (-not $SkipLeakCheck)
    {
        foreach ($leak in $leakPatterns)
        {
            $hits = [regex]::Matches($text, $leak.Pattern)

            if ($hits.Count -gt 0)
            {
                $sample = $hits[0].Value

                if ($sample.Length -gt 60)
                {
                    $sample = $sample.Substring(0, 57) + '...'
                }

                Add-Finding -Check 'Leaks' -File $rel -Detail "$($leak.Name): $($hits.Count) hit(s), first is '$sample'"
            }
        }
    }
}

$rootManifest   = Join-Path $Path 'plugin.json'
$claudeManifest = Join-Path $Path '.claude-plugin/plugin.json'

if ((Test-Path -LiteralPath $rootManifest) -and (Test-Path -LiteralPath $claudeManifest))
{
    $rootJson   = Get-Content -LiteralPath $rootManifest   -Raw | ConvertFrom-Json
    $claudeJson = Get-Content -LiteralPath $claudeManifest -Raw | ConvertFrom-Json

    foreach ($field in @('name', 'version', 'description', 'license'))
    {
        if ($rootJson.$field -ne $claudeJson.$field)
        {
            Add-Finding -Check 'Manifests' -File 'plugin.json' -Detail "Field '$field' differs between the two manifests."
        }
    }
}
else
{
    Add-Finding -Check 'Manifests' -File 'plugin.json' -Detail 'One or both plugin manifests are missing.'
}

$findings

Write-Host ''
Write-Host ("Checked {0} script(s) and {1} text file(s)." -f $scripts.Count, $textFiles.Count)

if ($findings.Count -eq 0)
{
    Write-Host 'All checks passed.'
    exit 0
}

foreach ($group in ($findings | Group-Object Check | Sort-Object Name))
{
    Write-Host ("  {0,-10} {1}" -f $group.Name, $group.Count)
}

Write-Host ''
Write-Host ("{0} finding(s)." -f $findings.Count)

exit 1
