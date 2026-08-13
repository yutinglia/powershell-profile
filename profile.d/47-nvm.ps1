function Get-NvmcVersions {
    <#
    .SYNOPSIS
        Internal helper for nvmc.
    #>
    function Get-NvmcHome {
        if ($env:NVM_HOME -and (Test-Path -LiteralPath $env:NVM_HOME -PathType Container)) {
            return $env:NVM_HOME
        }
        $cmd = Get-Command nvm -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) {
            $dir = Split-Path $cmd.Source -Parent
            if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) { return $dir }
        }
        return $null
    }

    function Get-NvmcNvmrc {
        $path = Join-Path (Get-Location) '.nvmrc'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $line = (Get-Content -LiteralPath $path -TotalCount 1 -ErrorAction SilentlyContinue)
        if (-not $line) { return $null }
        $line = $line.Trim()
        if (-not $line) { return $null }
        return $line
    }

    function Test-NvmcNvmrcMatch {
        param([string]$Version, [string]$Nvmrc)
        if (-not $Nvmrc) { return $false }
        $want = $Nvmrc.Trim() -replace '^v', ''
        if ($want -match '^(lts|latest|node)(/|$)') { return $false }
        if ($Version -eq $want) { return $true }
        return $Version.StartsWith("$want.")
    }

    $nvmHome = Get-NvmcHome
    if (-not $nvmHome) { return @() }

    # Read current from the nvm-windows symlink. Do not call nvm.exe — without a
    # real console it shows a "Terminal Only" MessageBox instead of stdout.
    $currentFolder = $null
    $symlink = $env:NVM_SYMLINK
    if (-not $symlink) {
        $settings = Join-Path $nvmHome 'settings.txt'
        if (Test-Path -LiteralPath $settings -PathType Leaf) {
            foreach ($raw in Get-Content -LiteralPath $settings -ErrorAction SilentlyContinue) {
                if ($raw -match '^path:\s*(.+)$') {
                    $symlink = $matches[1].Trim()
                    break
                }
            }
        }
    }
    if ($symlink -and (Test-Path -LiteralPath $symlink)) {
        $link = Get-Item -LiteralPath $symlink -ErrorAction SilentlyContinue
        $target = $null
        if ($link -and $link.Target) {
            $target = @($link.Target)[0]
        }
        if ($target) {
            $currentFolder = Split-Path ([System.IO.Path]::GetFullPath($target)) -Leaf
        }
    }

    $nvmrc = Get-NvmcNvmrc
    $found = [System.Collections.Generic.List[object]]::new()

    foreach ($dir in @(Get-ChildItem -LiteralPath $nvmHome -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Name -notmatch '^v?(\d+\.\d+\.\d+)$') { continue }
        $version = $matches[1]
        $found.Add([pscustomobject]@{
            Name       = $version
            Folder     = $dir.Name
            Path       = $dir.FullName
            Current    = [bool]($currentFolder -and $dir.Name -eq $currentFolder)
            Nvmrc      = $nvmrc
            NvmrcMatch = [bool](Test-NvmcNvmrcMatch $version $nvmrc)
        })
    }

    @($found | Sort-Object @{ Expression = { -not $_.NvmrcMatch } }, @{ Expression = { [version]$_.Name }; Descending = $true })
}

function nvmc {
    <#
    .SYNOPSIS
        Pick an installed nvm-windows Node version and switch to it.
    .DESCRIPTION
        Lists versions from NVM_HOME (does not call nvm.exe to list — nvm-windows
        pops a "Terminal Only" dialog when stdout is not a console).
        Enter runs `nvm use` which updates the machine symlink and affects other terminals.
        A unique exact version match switches immediately without opening the TUI.
        If cwd has a .nvmrc matching an installed version, that version is pinned at the top.
    .PARAMETER Filter
        Substring filter against version and folder name.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter
    )

    if (-not $script:NvmcCompleterRegistered) {
        $script:NvmcCompleterRegistered = $true
        Register-ArgumentCompleter -CommandName nvmc -ParameterName Filter -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            Get-NvmcVersions | ForEach-Object { $_.Name } | Sort-Object -Unique | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }

    $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
    if (-not $nvmCmd) {
        Write-Error 'nvm not found.'
        return
    }

    function Test-NvmcMatch {
        param($Item, [string]$Query)
        $Item.Name -like "*$Query*" -or
        $Item.Folder -like "*$Query*"
    }

    function Invoke-NvmcSelect {
        param($Item)
        Write-Host ''
        Write-Host '  ' -NoNewline
        Write-Host ([char]0xE718) -ForegroundColor Cyan -NoNewline
        Write-Host ' ' -NoNewline
        Write-Host $Item.Name -ForegroundColor Magenta -NoNewline
        Write-Host '  global nvm-windows symlink (other terminals too)' -ForegroundColor DarkGray
        Write-Host ''
        & nvm use $Item.Name
    }

    $entries = @(Get-NvmcVersions)
    if ($entries.Count -eq 0) {
        Write-Host 'No Node versions installed via nvm.'
        return
    }

    if ($Filter) {
        $exact = @($entries | Where-Object { $_.Name -eq $Filter -or $_.Folder -eq $Filter -or $_.Folder -eq "v$Filter" })
        if ($exact.Count -eq 1) {
            Invoke-NvmcSelect $exact[0]
            return
        }
        $matched = @($entries | Where-Object { Test-NvmcMatch $_ $Filter })
        if ($matched.Count -eq 0) {
            Write-Host "No Node versions matching filter: $Filter"
            return
        }
        if ($matched.Count -eq 1) {
            Invoke-NvmcSelect $matched[0]
            return
        }
    }

    $nameWidth = 12
    if ($entries.Count -gt 0) {
        $nameWidth = [Math]::Max(12, ($entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    }

    $picked = Invoke-ProfilePicker -Items $entries -Query $Filter `
        -Title ' nvm ' `
        -ListLabel 'Versions' `
        -Hint ' click/enter nvm use  ·  esc cancel  ·  type to filter ' `
        -FallbackPrompt 'Select Node version number (or q to cancel)' `
        -Filter {
            param($item, $query)
            Test-NvmcMatch $item $query
        } `
        -FormatRow {
            param($item)
            $mark = if ($item.Current) { '*' } else { ' ' }
            $tag = if ($item.NvmrcMatch) { '  nvmrc' } else { '' }
            '{0} {1}{2}' -f $mark, $item.Name.PadRight($nameWidth), $tag
        } `
        -FormatDetails {
            param($item)
            $lines = @(
                " VERSION   $($item.Name)"
                " CURRENT   $(if ($item.Current) { 'yes' } else { 'no' })"
                " PATH      $($item.Path)"
                " NOTE      nvm use is global (symlink)"
            )
            if ($item.Nvmrc) {
                $lines += " NVMRC     $($item.Nvmrc)"
            }
            else {
                $lines += ' NVMRC     -'
            }
            $lines
        } `
        -FormatFallback {
            param($item)
            $mark = if ($item.Current) { '*' } else { ' ' }
            '{0} {1}' -f $mark, $item.Name
        }

    if ($picked) { Invoke-NvmcSelect $picked }
}
