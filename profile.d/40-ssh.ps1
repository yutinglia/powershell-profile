function sshconf {
    <#
    .SYNOPSIS
        Open ~/.ssh/config in VS Code.
    #>
    code $env:USERPROFILE\.ssh\config
}

function sshls {
    <#
    .SYNOPSIS
        List Host entries from ~/.ssh/config.
    #>
    Get-Content "$env:USERPROFILE\.ssh\config" | Select-String "^Host\s+([^*]+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
}

function sshc {
    <#
    .SYNOPSIS
        Pick an SSH host from ~/.ssh/config and connect.
    #>
    [CmdletBinding()]
    param (
        [string]$Filter
    )

    $configPath = Join-Path $env:USERPROFILE '.ssh\config'
    if (-not (Test-Path $configPath)) {
        Write-Error "SSH config not found: $configPath"
        return
    }

    function Get-SshcHosts {
        param([string]$Path)

        $map = [ordered]@{}
        $current = @()
        $pendingNote = $null

        foreach ($raw in Get-Content -Path $Path) {
            $line = $raw.Trim()
            if ($line -match '^#\s*(.+)$') {
                if ($current.Count -eq 0) { $pendingNote = $matches[1].Trim() }
                continue
            }
            if (-not $line) { continue }

            if ($line -match '^(?i)Host\s+(.+)$') {
                $current = @()
                foreach ($name in ($matches[1] -split '\s+')) {
                    if (-not $name -or $name -match '[*?]') { continue }
                    $current += $name
                    if (-not $map.Contains($name)) {
                        $map[$name] = [pscustomobject]@{
                            Name         = $name
                            HostName     = $null
                            User         = $null
                            Port         = $null
                            IdentityFile = $null
                            ProxyJump    = $null
                            LocalForward = $null
                            Note         = $pendingNote
                        }
                    }
                }
                $pendingNote = $null
                continue
            }

            if ($current.Count -eq 0) { continue }
            if ($line -match '^(?i)(HostName|User|Port|IdentityFile|ProxyJump|LocalForward)\s+(.+)$') {
                $key = $matches[1]
                $val = $matches[2].Trim()
                foreach ($name in $current) {
                    $map[$name].$key = $val
                }
            }
        }

        @($map.Values)
    }

    function Get-SshcIcon {
        param([string]$Name)
        switch -Regex ($Name) {
            'github'         { return [char]0xF09B }
            'mac'            { return [char]0xF179 }
            'aws'            { return [char]0xF0C2 }
            'tunnel|vnc'     { return [char]0xF0C1 }
            'pve|opnsense'   { return [char]0xF233 }
            default          { return [char]0xF120 }
        }
    }

    function Get-SshcTarget {
        param($HostEntry)
        $user = $HostEntry.User
        $addr = if ($HostEntry.HostName) { $HostEntry.HostName } else { $HostEntry.Name }
        $target = if ($user) { "${user}@${addr}" } else { $addr }
        if ($HostEntry.Port -and $HostEntry.Port -ne '22') { $target = "${target}:$($HostEntry.Port)" }
        $target
    }

    function Connect-SshcHost {
        param($HostEntry)
        $target = Get-SshcTarget $HostEntry
        Write-Host ''
        Write-Host '  ' -NoNewline
        Write-Host (Get-SshcIcon $HostEntry.Name) -ForegroundColor Cyan -NoNewline
        Write-Host ' Connecting to ' -NoNewline
        Write-Host $HostEntry.Name -ForegroundColor Magenta -NoNewline
        Write-Host "  $target" -ForegroundColor DarkGray
        Write-Host ''
        & ssh $HostEntry.Name
    }

    $entries = @(Get-SshcHosts -Path $configPath | Sort-Object Name)
    if ($entries.Count -eq 0) {
        Write-Host 'No hosts found in SSH config.'
        return
    }

    if ($Filter) {
        $exact = @($entries | Where-Object { $_.Name -eq $Filter })
        if ($exact.Count -eq 1) {
            Connect-SshcHost $exact[0]
            return
        }
        $matched = @($entries | Where-Object {
            $_.Name -like "*$Filter*" -or
            $_.HostName -like "*$Filter*" -or
            $_.User -like "*$Filter*"
        })
        if ($matched.Count -eq 0) {
            Write-Host "No hosts found matching filter: $Filter"
            return
        }
        if ($matched.Count -eq 1) {
            Connect-SshcHost $matched[0]
            return
        }
    }

    $nameWidth = 12
    if ($entries.Count -gt 0) {
        $nameWidth = [Math]::Max(12, ($entries | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    }

    $picked = Invoke-ProfilePicker -Items $entries -Query $Filter `
        -Title ' SSH Connect ' `
        -ListLabel 'Hosts' `
        -Hint ' click/enter connect  ·  esc cancel  ·  ctrl-e edit  ·  type to filter ' `
        -FallbackPrompt 'Select host number (or q to cancel)' `
        -Filter {
            param($item, $query)
            $item.Name -like "*$query*" -or
            $item.HostName -like "*$query*" -or
            $item.User -like "*$query*"
        } `
        -FormatRow {
            param($item)
            $tags = @()
            if ($item.ProxyJump) { $tags += "via $($item.ProxyJump)" }
            if ($item.LocalForward) { $tags += 'tunnel' }
            $tagText = if ($tags) { '  ' + ($tags -join '  ') } else { '' }
            '{0}  {1}{2}' -f $item.Name.PadRight($nameWidth), (Get-SshcTarget $item), $tagText
        } `
        -FormatDetails {
            param($item)
            $lines = @(
                " HOST      $($item.Name)"
                " USER      $(if ($item.User) { $item.User } else { '-' })"
                " ADDRESS   $(if ($item.HostName) { $item.HostName } else { '-' })"
                " PORT      $(if ($item.Port) { $item.Port } else { '22' })"
                " KEY       $(if ($item.IdentityFile) { Split-Path $item.IdentityFile -Leaf } else { '-' })"
                " JUMP      $(if ($item.ProxyJump) { $item.ProxyJump } else { '-' })"
                " TUNNEL    $(if ($item.LocalForward) { $item.LocalForward } else { '-' })"
            )
            if ($item.Note) { $lines += " NOTE      $($item.Note)" }
            $lines
        } `
        -FormatFallback {
            param($item)
            '{0,-20} {1}' -f $item.Name, (Get-SshcTarget $item)
        } `
        -OnKey @{
            E = {
                param($item)
                if ($configPath) { code $configPath }
            }
        }

    if ($picked) { Connect-SshcHost $picked }
}

Register-ArgumentCompleter -CommandName sshc -ParameterName Filter -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    sshls | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
