function Get-CondacEnvs {
    function Get-CondacCondaExe {
        foreach ($candidate in @(
            $env:CONDA_EXE
            $(if ($env:_CONDA_ROOT) { Join-Path $env:_CONDA_ROOT 'Scripts\conda.exe' })
            $(if ($env:CONDA_ROOT) { Join-Path $env:CONDA_ROOT 'Scripts\conda.exe' })
        )) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                return $candidate
            }
        }
        $cmd = Get-Command conda.exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { return $cmd.Source }
        return $null
    }

    $exe = Get-CondacCondaExe
    if (-not $exe) { return @() }

    $raw = (& $exe env list --json 2>$null | Out-String)
    if (-not $raw) { return @() }
    $start = $raw.IndexOf('{')
    $end = $raw.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) { return @() }

    try {
        $json = $raw.Substring($start, $end - $start + 1) | ConvertFrom-Json
    }
    catch {
        return @()
    }

    $root = $null
    foreach ($candidate in @($json.root_prefix, $env:_CONDA_ROOT, $env:CONDA_ROOT)) {
        if ($candidate) {
            $root = [System.IO.Path]::GetFullPath($candidate)
            break
        }
    }

    $active = $null
    foreach ($candidate in @($env:CONDA_PREFIX, $json.active_prefix)) {
        if ($candidate) {
            $active = [System.IO.Path]::GetFullPath($candidate)
            break
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $found = [System.Collections.Generic.List[object]]::new()

    foreach ($prefix in @($json.envs)) {
        if (-not $prefix) { continue }
        $full = [System.IO.Path]::GetFullPath($prefix)
        if (-not $seen.Add($full)) { continue }

        $isRoot = $root -and ($full -eq $root)
        $name = if ($isRoot) { 'base' } else { Split-Path $full -Leaf }
        $rel = $full
        if ($root -and $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $full.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
            if (-not $rel) { $rel = '.' }
        }
        else {
            $rel = $full.Replace('\', '/')
        }

        $found.Add([pscustomobject]@{
            Kind      = 'env'
            Name      = $name
            Prefix    = $full
            RelPrefix = $rel
            Active    = [bool]($active -and $full -eq $active)
        })
    }

    @($found)
}

function condac {
    <#
    .SYNOPSIS
        Pick a conda environment and activate it in this session.
    .DESCRIPTION
        Lists conda envs via `conda env list --json` and opens a native TUI.
        Enter activates the selected env using the conda PowerShell hook (AllHosts profile.ps1).
        A unique exact name match activates immediately without opening the TUI.
        If an env is active, `(deactivate)` is pinned at the top.
    .PARAMETER Filter
        Substring filter against name and prefix.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter
    )

    $condaCmd = Get-Command conda -ErrorAction SilentlyContinue
    if (-not $condaCmd) {
        Write-Error 'conda not found.'
        return
    }
    if ($condaCmd.CommandType -eq 'Application') {
        Write-Error 'conda hook is not loaded. AllHosts profile.ps1 should run conda init; do not fold it into CurrentUser fragments.'
        return
    }

    function Test-CondacMatch {
        param($Item, [string]$Query)
        $Item.Name -like "*$Query*" -or
        ($Item.Prefix -and $Item.Prefix -like "*$Query*") -or
        ($Item.RelPrefix -and $Item.RelPrefix -like "*$Query*") -or
        ($Item.Kind -eq 'deactivate' -and 'deactivate' -like "*$Query*")
    }

    function Test-CondacExact {
        param($Item, [string]$Query)
        $Item.Name -eq $Query -or
        ($Item.Kind -eq 'deactivate' -and $Query -eq 'deactivate')
    }

    function Invoke-CondacSelect {
        param($Item)
        Write-Host ''
        Write-Host '  ' -NoNewline
        if ($Item.Kind -eq 'deactivate') {
            Write-Host ([char]0xF057) -ForegroundColor Cyan -NoNewline
            Write-Host ' ' -NoNewline
            Write-Host 'deactivate' -ForegroundColor Magenta
            Write-Host ''
            conda deactivate
            return
        }

        Write-Host ([char]0xE235) -ForegroundColor Cyan -NoNewline
        Write-Host ' ' -NoNewline
        Write-Host $Item.Name -ForegroundColor Magenta -NoNewline
        Write-Host "  $($Item.Prefix)" -ForegroundColor DarkGray
        Write-Host ''
        conda activate $Item.Prefix
    }

    $envs = @(Get-CondacEnvs)
    if ($envs.Count -eq 0) {
        Write-Host 'No conda environments found.'
        return
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $anyActive = [bool]($envs | Where-Object { $_.Active })
    if ($anyActive) {
        $entries.Add([pscustomobject]@{
            Kind      = 'deactivate'
            Name      = '(deactivate)'
            Prefix    = $null
            RelPrefix = ''
            Active    = $false
        })
    }
    foreach ($envItem in @($envs | Sort-Object @{ Expression = { -not $_.Active } }, Name)) {
        $entries.Add($envItem)
    }
    $entries = @($entries)

    if ($Filter) {
        $exact = @($entries | Where-Object { Test-CondacExact $_ $Filter })
        if ($exact.Count -eq 1) {
            Invoke-CondacSelect $exact[0]
            return
        }
        $matched = @($entries | Where-Object { Test-CondacMatch $_ $Filter })
        if ($matched.Count -eq 0) {
            Write-Host "No conda environments matching filter: $Filter"
            return
        }
        if ($matched.Count -eq 1) {
            Invoke-CondacSelect $matched[0]
            return
        }
    }

    $nameWidth = 12
    if ($entries.Count -gt 0) {
        $nameWidth = [Math]::Max(12, ($entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    }

    $picked = Invoke-ProfilePicker -Items $entries -Query $Filter `
        -Title ' Conda ' `
        -ListLabel 'Envs' `
        -Hint ' click/enter activate  ·  esc cancel  ·  type to filter ' `
        -FallbackPrompt 'Select conda env number (or q to cancel)' `
        -Filter {
            param($item, $query)
            Test-CondacMatch $item $query
        } `
        -FormatRow {
            param($item)
            $mark = if ($item.Active) { '*' } else { ' ' }
            '{0} {1}  {2}' -f $mark, $item.Name.PadRight($nameWidth), $item.RelPrefix
        } `
        -FormatDetails {
            param($item)
            if ($item.Kind -eq 'deactivate') {
                return @(
                    ' ACTION    conda deactivate'
                    ' NOTE      leaves the current env in this session'
                )
            }
            @(
                " NAME      $($item.Name)"
                " PREFIX    $($item.Prefix)"
                " ACTIVE    $(if ($item.Active) { 'yes' } else { 'no' })"
            )
        } `
        -FormatFallback {
            param($item)
            $mark = if ($item.Active) { '*' } else { ' ' }
            '{0} {1,-20} {2}' -f $mark, $item.Name, $item.RelPrefix
        }

    if ($picked) { Invoke-CondacSelect $picked }
}

Register-ArgumentCompleter -CommandName condac -ParameterName Filter -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $names = [System.Collections.Generic.List[string]]::new()
    $names.Add('deactivate')
    Get-CondacEnvs | ForEach-Object { $names.Add($_.Name) }
    $names | Sort-Object -Unique | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
