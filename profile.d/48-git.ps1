function Invoke-GitcGit {
    <#
    .SYNOPSIS
        Internal helper for gitc and repo.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [switch]$Quiet
    )

    $prevEap = $ErrorActionPreference
    $hadNative = Test-Path variable:PSNativeCommandUseErrorActionPreference
    $prevNative = if ($hadNative) { $PSNativeCommandUseErrorActionPreference } else { $null }
    $ErrorActionPreference = 'SilentlyContinue'
    if ($hadNative) { $PSNativeCommandUseErrorActionPreference = $false }
    try {
        if ($Quiet) {
            return (& git @ArgumentList 2>$null)
        }
        & git @ArgumentList
    }
    finally {
        $ErrorActionPreference = $prevEap
        if ($hadNative) { $PSNativeCommandUseErrorActionPreference = $prevNative }
    }
}

function Get-GitcRoot {
    <#
    .SYNOPSIS
        Internal helper for gitc and repo.
    #>
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $out = Invoke-GitcGit -ArgumentList @('rev-parse', '--show-toplevel') -Quiet
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return ([string]$out).Trim()
}

function Get-GitcBranches {
    <#
    .SYNOPSIS
        Internal helper for gitc.
    #>
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return @() }

    $sep = [char]0x1f
    $fmt = @(
        '%(refname)'
        '%(refname:short)'
        '%(objectname:short)'
        '%(committerdate:relative)'
        '%(subject)'
        '%(upstream:short)'
        '%(upstream:track)'
        '%(HEAD)'
    ) -join $sep

    $lines = @(Invoke-GitcGit -ArgumentList @(
        'for-each-ref'
        '--sort=-committerdate'
        "--format=$fmt"
        'refs/heads/'
        'refs/remotes/'
    ) -Quiet)
    if ($LASTEXITCODE -ne 0) { return @() }

    $found = [System.Collections.Generic.List[object]]::new()
    $localNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    foreach ($line in $lines) {
        if (-not $line) { continue }
        $parts = $line.Split($sep)
        if ($parts.Count -lt 8) { continue }

        $refname = $parts[0].Trim()
        if ($refname -match '^refs/remotes/.+/HEAD$') { continue }

        $kind = if ($refname.StartsWith('refs/heads/')) { 'local' } else { 'remote' }
        $short = $parts[1].Trim()
        $localName = $short
        $remoteName = $null
        if ($kind -eq 'remote' -and $refname -match '^refs/remotes/([^/]+)/(.+)$') {
            $remoteName = $matches[1]
            $localName = $matches[2]
        }
        if ($kind -eq 'local') { [void]$localNames.Add($localName) }

        $found.Add([pscustomobject]@{
            Name      = $short
            LocalName = $localName
            Kind      = $kind
            Remote    = $remoteName
            RefName   = $refname
            Sha       = $parts[2].Trim()
            When      = $parts[3].Trim()
            Subject   = $parts[4].Trim()
            Upstream  = $parts[5].Trim()
            Track     = $parts[6].Trim()
            Current   = ($parts[7].Trim() -eq '*')
        })
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $found) {
        if ($item.Kind -eq 'remote' -and $localNames.Contains($item.LocalName)) { continue }
        $entries.Add($item)
    }

    @($entries | Sort-Object @{ Expression = { -not $_.Current } }, @{ Expression = { $_.Kind -ne 'local' } })
}

function gitc {
    <#
    .SYNOPSIS
        Pick a local or remote git branch and check it out.
    .DESCRIPTION
        Lists local branches and remote-only branches, then opens a native TUI.
        Enter (or double-click) runs git checkout. Remote-only refs use --track.
        A unique exact name match checks out immediately without opening the TUI.
        The details pane shows upstream, last commit, and worktree dirty status.
    .PARAMETER Filter
        Substring filter against branch name, kind, upstream, and subject.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Error 'git not found.'
        return
    }

    $root = Get-GitcRoot
    if (-not $root) {
        Write-Error 'Not a git repository.'
        return
    }

    function Test-GitcMatch {
        param($Item, [string]$Query)
        $Item.Name -like "*$Query*" -or
        $Item.LocalName -like "*$Query*" -or
        $Item.Kind -like "*$Query*" -or
        ($Item.Upstream -and $Item.Upstream -like "*$Query*") -or
        ($Item.Subject -and $Item.Subject -like "*$Query*")
    }

    function Test-GitcExact {
        param($Item, [string]$Query)
        $Item.Name -eq $Query -or $Item.LocalName -eq $Query
    }

    function Get-GitcWorktreeStatus {
        $files = @(Invoke-GitcGit -ArgumentList @('status', '--porcelain=v1') -Quiet | Where-Object { $_ })
        $summary = if ($files.Count -eq 0) { 'clean' } else { "dirty ($($files.Count) files)" }
        [pscustomobject]@{
            Dirty   = $files.Count -gt 0
            Count   = $files.Count
            Summary = $summary
            Files   = $files
        }
    }

    function Invoke-GitcCheckout {
        param($Item)
        Write-Host ''
        Write-Host '  ' -NoNewline
        Write-Host ([char]0xE725) -ForegroundColor Cyan -NoNewline
        Write-Host ' ' -NoNewline
        if ($Item.Current) {
            Write-Host $Item.Name -ForegroundColor Magenta -NoNewline
            Write-Host '  already checked out' -ForegroundColor DarkGray
            Write-Host ''
            return
        }

        Write-Host $Item.Name -ForegroundColor Magenta -NoNewline
        Write-Host "  $($Item.Kind)" -ForegroundColor DarkGray
        Write-Host ''
        if ($Item.Kind -eq 'local') {
            Invoke-GitcGit -ArgumentList @('checkout', $Item.Name)
        }
        else {
            Invoke-GitcGit -ArgumentList @('checkout', '--track', $Item.Name)
        }
    }

    $entries = @(Get-GitcBranches)
    if ($entries.Count -eq 0) {
        Write-Host 'No branches found.'
        return
    }

    if ($Filter) {
        $exact = @($entries | Where-Object { Test-GitcExact $_ $Filter })
        if ($exact.Count -eq 1) {
            Invoke-GitcCheckout $exact[0]
            return
        }
        $matched = @($entries | Where-Object { Test-GitcMatch $_ $Filter })
        if ($matched.Count -eq 0) {
            Write-Host "No branches found matching filter: $Filter"
            return
        }
        if ($matched.Count -eq 1) {
            Invoke-GitcCheckout $matched[0]
            return
        }
    }

    $status = Get-GitcWorktreeStatus
    $nameWidth = 12
    if ($entries.Count -gt 0) {
        $nameWidth = [Math]::Max(12, ($entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    }

    $picked = Invoke-ProfilePicker -Items $entries -Query $Filter `
        -Title ' gitc ' `
        -ListLabel 'Branches' `
        -Hint ' click/enter checkout  ·  esc cancel  ·  type to filter ' `
        -FallbackPrompt 'Select branch number (or q to cancel)' `
        -Filter {
            param($item, $query)
            Test-GitcMatch $item $query
        } `
        -FormatRow {
            param($item)
            $mark = if ($item.Current) { '*' } else { ' ' }
            '{0} {1}  {2}  {3}' -f $mark, $item.Name.PadRight($nameWidth), $item.Kind.PadRight(6), $item.When
        } `
        -FormatDetails {
            param($item)
            $upstream = '-'
            if ($item.Upstream) {
                $upstream = if ($item.Track) { "$($item.Upstream) $($item.Track)" } else { $item.Upstream }
            }
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add(" BRANCH    $($item.Name)")
            $lines.Add(" KIND      $($item.Kind)")
            $lines.Add(" CURRENT   $(if ($item.Current) { 'yes' } else { 'no' })")
            $lines.Add(" UPSTREAM  $upstream")
            $lines.Add(" COMMIT    $(if ($item.Sha) { $item.Sha } else { '-' })")
            $lines.Add(" WHEN      $(if ($item.When) { $item.When } else { '-' })")
            $lines.Add(" SUBJECT   $(if ($item.Subject) { $item.Subject } else { '-' })")
            $lines.Add(" STATUS    $($status.Summary)")
            $lines.Add(" ROOT      $root")
            $shown = 0
            foreach ($file in $status.Files) {
                if ($shown -ge 6) { break }
                $lines.Add("           $file")
                $shown++
            }
            if ($status.Count -gt 6) {
                $lines.Add("           ... +$($status.Count - 6) more")
            }
            @($lines)
        } `
        -FormatFallback {
            param($item)
            $mark = if ($item.Current) { '*' } else { ' ' }
            '{0} {1,-24} {2}' -f $mark, $item.Name, $item.Kind
        }

    if ($picked) { Invoke-GitcCheckout $picked }
}

function repo {
    <#
    .SYNOPSIS
        Change location to the current git worktree root.
    #>
    $root = Get-GitcRoot
    if (-not $root) {
        Write-Error 'Not a git repository.'
        return
    }
    Set-Location -LiteralPath $root
}

Register-ArgumentCompleter -CommandName gitc -ParameterName Filter -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-GitcBranches | ForEach-Object { $_.Name; $_.LocalName } | Sort-Object -Unique | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
