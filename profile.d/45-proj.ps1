function Get-ProjRepos {
    function Resolve-ProjPath {
        param([string]$Base, [string]$Path)
        $Path = $Path.Trim()
        if ([System.IO.Path]::IsPathRooted($Path)) {
            return [System.IO.Path]::GetFullPath($Path)
        }
        return [System.IO.Path]::GetFullPath((Join-Path $Base $Path))
    }

    function Get-ProjGitDir {
        param([string]$RepoPath)
        $git = Join-Path $RepoPath '.git'
        $item = Get-Item -LiteralPath $git -Force -ErrorAction SilentlyContinue
        if (-not $item) { return $null }
        if ($item.PSIsContainer) { return $item.FullName }
        $text = (Get-Content -LiteralPath $item.FullName -TotalCount 1 -ErrorAction SilentlyContinue)
        if ($text -match '^gitdir:\s*(.+)$') {
            return (Resolve-ProjPath $RepoPath $matches[1])
        }
        return $null
    }

    function Get-ProjGitCommonDir {
        param([string]$GitDir)
        $commondirFile = Join-Path $GitDir 'commondir'
        if (-not (Test-Path -LiteralPath $commondirFile -PathType Leaf)) { return $GitDir }
        $common = (Get-Content -LiteralPath $commondirFile -TotalCount 1 -ErrorAction SilentlyContinue)
        if (-not $common) { return $GitDir }
        return (Resolve-ProjPath $GitDir $common)
    }

    function Get-ProjBranch {
        param([string]$GitDir)
        $head = Join-Path $GitDir 'HEAD'
        if (-not (Test-Path -LiteralPath $head -PathType Leaf)) { return $null }
        $line = (Get-Content -LiteralPath $head -TotalCount 1 -ErrorAction SilentlyContinue)
        if (-not $line) { return $null }
        $line = $line.Trim()
        if ($line -match '^ref:\s*refs/heads/(.+)$') { return $matches[1] }
        if ($line -match '^[0-9a-fA-F]{7,40}$') { return $line.Substring(0, [Math]::Min(7, $line.Length)) }
        return $line
    }

    function Get-ProjRemote {
        param([string]$ConfigDir)
        $config = Join-Path $ConfigDir 'config'
        if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return $null }
        $inOrigin = $false
        foreach ($raw in Get-Content -LiteralPath $config -ErrorAction SilentlyContinue) {
            $line = $raw.Trim()
            if ($line -match '^\[remote "origin"\]') { $inOrigin = $true; continue }
            if ($line -match '^\[') { $inOrigin = $false; continue }
            if ($inOrigin -and $line -match '^url\s*=\s*(.+)$') { return $matches[1].Trim() }
        }
        return $null
    }

    $root = $env:WORK_ROOT
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return @() }

    $rootFull = [System.IO.Path]::GetFullPath((Get-Item -LiteralPath $root).FullName)
    $skip = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('node_modules', '.git', 'vendor', 'dist', '.venv'),
        [StringComparer]::OrdinalIgnoreCase
    )
    $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $found = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{ Path = $rootFull; Depth = 0 })

    while ($queue.Count -gt 0) {
        $cur = $queue.Dequeue()
        if (-not $visited.Add($cur.Path)) { continue }

        $gitDir = Get-ProjGitDir $cur.Path
        if ($gitDir) {
            $commonDir = Get-ProjGitCommonDir $gitDir
            $rel = $cur.Path.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
            if (-not $rel) { $rel = '.' }
            $found.Add([pscustomobject]@{
                Name   = Split-Path $cur.Path -Leaf
                Path   = $cur.Path
                RelPath = $rel
                Branch = Get-ProjBranch $gitDir
                Remote = Get-ProjRemote $commonDir
            })
        }

        if ($cur.Depth -ge 3) { continue }
        foreach ($child in @(Get-ChildItem -LiteralPath $cur.Path -Directory -ErrorAction SilentlyContinue)) {
            if ($skip.Contains($child.Name)) { continue }
            $queue.Enqueue([pscustomobject]@{ Path = $child.FullName; Depth = $cur.Depth + 1 })
        }
    }

    @($found | Sort-Object RelPath)
}

function proj {
    <#
    .SYNOPSIS
        Pick a git repo under WORK_ROOT and cd into it.
    .DESCRIPTION
        Scans git repositories under $env:WORK_ROOT (D:/work) and opens a native TUI.
        Enter (or double-click) changes location to the selected repo. Ctrl+E opens it in VS Code.
        A unique exact name match cds immediately without opening the TUI.
    .PARAMETER Filter
        Substring filter against name, relative path, remote, and branch.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter
    )

    $root = $env:WORK_ROOT
    if (-not $root -or -not (Test-Path -LiteralPath $root)) {
        Write-Error "Work root not found: $root"
        return
    }

    function Test-ProjMatch {
        param($Item, [string]$Query)
        $Item.Name -like "*$Query*" -or
        $Item.RelPath -like "*$Query*" -or
        $Item.Remote -like "*$Query*" -or
        $Item.Branch -like "*$Query*"
    }

    function Get-ProjStatus {
        param([string]$Path)
        try {
            $output = & git -C $Path status --porcelain 2>$null
            if ($LASTEXITCODE -ne 0) { return 'unknown' }
            if ($output) { return 'dirty' }
            return 'clean'
        }
        catch {
            return 'unknown'
        }
    }

    function Enter-ProjRepo {
        param($Repo)
        Write-Host ''
        Write-Host '  ' -NoNewline
        Write-Host ([char]0xF07B) -ForegroundColor Cyan -NoNewline
        Write-Host ' ' -NoNewline
        Write-Host $Repo.Name -ForegroundColor Magenta -NoNewline
        Write-Host "  $($Repo.Path)" -ForegroundColor DarkGray
        Write-Host ''
        Set-Location -LiteralPath $Repo.Path
    }

    $entries = @(Get-ProjRepos)
    if ($entries.Count -eq 0) {
        Write-Host "No git repositories found under $root"
        return
    }

    if ($Filter) {
        $exact = @($entries | Where-Object { $_.Name -eq $Filter })
        if ($exact.Count -eq 1) {
            Enter-ProjRepo $exact[0]
            return
        }
        $matched = @($entries | Where-Object { Test-ProjMatch $_ $Filter })
        if ($matched.Count -eq 0) {
            Write-Host "No projects found matching filter: $Filter"
            return
        }
        if ($matched.Count -eq 1) {
            Enter-ProjRepo $matched[0]
            return
        }
    }

    $nameWidth = 12
    if ($entries.Count -gt 0) {
        $nameWidth = [Math]::Max(12, ($entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    }

    $picked = Invoke-ProfilePicker -Items $entries -Query $Filter `
        -Title ' Projects ' `
        -ListLabel 'Projects' `
        -Hint ' click/enter cd  ·  esc cancel  ·  ctrl-e code  ·  type to filter ' `
        -FallbackPrompt 'Select project number (or q to cancel)' `
        -Filter {
            param($item, $query)
            Test-ProjMatch $item $query
        } `
        -FormatRow {
            param($item)
            $branch = if ($item.Branch) { $item.Branch } else { '-' }
            '{0}  {1}  {2}' -f $item.Name.PadRight($nameWidth), $item.RelPath, $branch
        } `
        -FormatDetails {
            param($item)
            @(
                " PATH      $($item.Path)"
                " REL       $($item.RelPath)"
                " BRANCH    $(if ($item.Branch) { $item.Branch } else { '-' })"
                " REMOTE    $(if ($item.Remote) { $item.Remote } else { '-' })"
                " STATUS    $(Get-ProjStatus $item.Path)"
            )
        } `
        -FormatFallback {
            param($item)
            '{0,-20} {1}' -f $item.Name, $item.RelPath
        } `
        -OnKey @{
            E = {
                param($item)
                if ($item -and $item.Path) { code $item.Path }
            }
        }

    if ($picked) { Enter-ProjRepo $picked }
}

Register-ArgumentCompleter -CommandName proj -ParameterName Filter -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    Get-ProjRepos | ForEach-Object { $_.Name } | Sort-Object -Unique | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
