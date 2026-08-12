function sshconf {
    code $env:USERPROFILE\.ssh\config
}

function sshls {
    Get-Content "$env:USERPROFILE\.ssh\config" | Select-String "^Host\s+([^*]+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
}

function sshc {
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

    function Show-SshcFallbackMenu {
        param($Entries)
        for ($i = 0; $i -lt $Entries.Count; $i++) {
            $entry = $Entries[$i]
            Write-Host ('  [{0}] {1,-20} {2}' -f ($i + 1), $entry.Name, (Get-SshcTarget $entry))
        }
        while ($true) {
            $choice = Read-Host 'Select host number (or q to cancel)'
            if ($choice -eq 'q') { Write-Host 'Cancelled.'; return $null }
            if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Entries.Count) {
                return $Entries[[int]$choice - 1]
            }
            Write-Host "Invalid selection. Enter 1-$($Entries.Count), or q to cancel."
        }
    }

    function ConvertTo-SshcRgb {
        param([string]$Hex)
        @(
            [Convert]::ToInt32($Hex.Substring(1, 2), 16)
            [Convert]::ToInt32($Hex.Substring(3, 2), 16)
            [Convert]::ToInt32($Hex.Substring(5, 2), 16)
        )
    }

    function Get-SshcSgr {
        param([string]$Fg, [string]$Bg, [switch]$Bold)
        $parts = @()
        if ($Bold) { $parts += '1' }
        if ($Fg) {
            $rgb = ConvertTo-SshcRgb $Fg
            $parts += "38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
        }
        if ($Bg) {
            $rgb = ConvertTo-SshcRgb $Bg
            $parts += "48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
        }
        "$([char]27)[$($parts -join ';')m"
    }

    function Limit-SshcText {
        param([string]$Text, [int]$Width)
        if ($Width -le 0) { return '' }
        if ($null -eq $Text) { $Text = '' }
        if ($Text.Length -le $Width) { return $Text.PadRight($Width) }
        if ($Width -eq 1) { return $Text.Substring(0, 1) }
        return $Text.Substring(0, $Width - 1) + [char]0x2026
    }

    function Initialize-SshcNativeConsole {
        if ('SshcNativeConsole' -as [type]) { return }
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SshcNativeConsole {
    public const int STD_INPUT_HANDLE = -10;
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
}
'@
    }

    function Read-SshcTuiInput {
        $k = [Console]::ReadKey($true)
        $ctrl = [ConsoleModifiers]::Control

        if (($k.Modifiers -band $ctrl) -and $k.Key -eq [ConsoleKey]::C) { return @{ Type = 'cancel' } }
        if (($k.Modifiers -band $ctrl) -and $k.Key -eq [ConsoleKey]::E) { return @{ Type = 'edit' } }
        if (($k.Modifiers -band $ctrl) -and $k.Key -eq [ConsoleKey]::U) { return @{ Type = 'clear' } }

        switch ($k.Key) {
            ([ConsoleKey]::Enter) { return @{ Type = 'enter' } }
            ([ConsoleKey]::UpArrow) { return @{ Type = 'up' } }
            ([ConsoleKey]::DownArrow) { return @{ Type = 'down' } }
            ([ConsoleKey]::PageUp) { return @{ Type = 'pageup' } }
            ([ConsoleKey]::PageDown) { return @{ Type = 'pagedown' } }
            ([ConsoleKey]::Home) { return @{ Type = 'home' } }
            ([ConsoleKey]::End) { return @{ Type = 'end' } }
            ([ConsoleKey]::Backspace) { return @{ Type = 'backspace' } }
            ([ConsoleKey]::Delete) { return @{ Type = 'backspace' } }
            ([ConsoleKey]::Tab) { return @{ Type = 'down' } }
        }

        $isEsc = ($k.Key -eq [ConsoleKey]::Escape) -or ($k.KeyChar -eq [char]27)
        if ($isEsc) {
            $seq = [System.Text.StringBuilder]::new()
            [void]$seq.Append([char]27)
            $waitMs = 25
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt $waitMs) {
                if ([Console]::KeyAvailable) {
                    $next = [Console]::ReadKey($true)
                    [void]$seq.Append($next.KeyChar)
                    $sw.Restart()
                    $waitMs = 8
                }
            }
            $s = $seq.ToString()
            if ($s.Length -eq 1) { return @{ Type = 'cancel' } }

            $mouse = [regex]::Match($s, [char]27 + '\[<(\d+);(\d+);(\d+)([Mm])')
            if ($mouse.Success) {
                return @{
                    Type   = 'mouse'
                    Button = [int]$mouse.Groups[1].Value
                    X      = [int]$mouse.Groups[2].Value
                    Y      = [int]$mouse.Groups[3].Value
                    Down   = $mouse.Groups[4].Value -eq 'M'
                }
            }
            if ($s.Contains([char]27 + '[A')) { return @{ Type = 'up' } }
            if ($s.Contains([char]27 + '[B')) { return @{ Type = 'down' } }
            if ($s.Contains([char]27 + '[5~')) { return @{ Type = 'pageup' } }
            if ($s.Contains([char]27 + '[6~')) { return @{ Type = 'pagedown' } }
            return @{ Type = 'none' }
        }

        if ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) {
            return @{ Type = 'char'; Char = [string]$k.KeyChar }
        }
        return @{ Type = 'none' }
    }

    function Show-SshcTui {
        param(
            $Entries,
            [string]$Query,
            [string]$ConfigPath
        )

        $esc = [char]27
        $reset = "$esc[0m"
        $bg = '#282a36'
        $fg = '#f8f8f2'
        $current = '#44475a'
        $purple = '#bd93f9'
        $green = '#50fa7b'
        $cyan = '#8be9fd'
        $pink = '#ff79c6'
        $comment = '#6272a4'
        $sgrBg = Get-SshcSgr -Fg $fg -Bg $bg
        $sgrBorder = Get-SshcSgr -Fg $comment -Bg $bg
        $sgrTitle = Get-SshcSgr -Fg $purple -Bg $bg -Bold
        $sgrSearch = Get-SshcSgr -Fg $cyan -Bg $bg
        $sgrGhost = Get-SshcSgr -Fg $comment -Bg $bg
        $sgrSel = Get-SshcSgr -Fg $green -Bg $current -Bold
        $sgrItem = Get-SshcSgr -Fg $fg -Bg $bg
        $sgrDim = Get-SshcSgr -Fg $comment -Bg $bg
        $sgrAccent = Get-SshcSgr -Fg $pink -Bg $bg
        $sgrLabel = Get-SshcSgr -Fg $green -Bg $bg
        $pointer = [char]0x25B6

        $queryText = if ($Query) { $Query } else { '' }
        $selected = 0
        $scroll = 0
        $lastClickIndex = -1
        $lastClickAt = [datetime]::MinValue

        Initialize-SshcNativeConsole
        $inputHandle = [SshcNativeConsole]::GetStdHandle(-10)
        $savedMode = [uint32]0
        $hasSavedMode = [SshcNativeConsole]::GetConsoleMode($inputHandle, [ref]$savedMode)
        if ($hasSavedMode) {
            $newMode = $savedMode
            $newMode = $newMode -bor [uint32]0x0080  # EXTENDED_FLAGS
            $newMode = $newMode -bor [uint32]0x0010  # MOUSE_INPUT
            $newMode = $newMode -bor [uint32]0x0200  # VT_INPUT
            $newMode = $newMode -band (-bnot [uint32]0x0040)  # ~QUICK_EDIT
            $newMode = $newMode -band (-bnot [uint32]0x0002)  # ~LINE_INPUT
            $newMode = $newMode -band (-bnot [uint32]0x0004)  # ~ECHO_INPUT
            [void][SshcNativeConsole]::SetConsoleMode($inputHandle, $newMode)
        }

        $savedTreatCtrlC = [Console]::TreatControlCAsInput
        $savedCursor = [Console]::CursorVisible
        $savedOutputEncoding = [Console]::OutputEncoding
        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible = $false
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            [Console]::Write("$esc[?1049h$esc[?25l$esc[?7l$esc[?1000h$esc[?1006h$esc[?1002h")

            while ($true) {
                $view = @($Entries)
                if ($queryText) {
                    $view = @($Entries | Where-Object {
                        $_.Name -like "*$queryText*" -or
                        $_.HostName -like "*$queryText*" -or
                        $_.User -like "*$queryText*"
                    })
                }

                if ($view.Count -eq 0) {
                    $selected = 0
                    $scroll = 0
                }
                else {
                    if ($selected -lt 0) { $selected = 0 }
                    if ($selected -ge $view.Count) { $selected = $view.Count - 1 }
                }

                $w = [Console]::WindowWidth
                $h = [Console]::WindowHeight
                if ($w -lt 40) { $w = 40 }
                if ($h -lt 12) { $h = 12 }

                $showDetails = $w -ge 72
                $detailW = if ($showDetails) { [Math]::Max(28, [int][Math]::Floor($w * 0.40)) } else { 0 }
                $listW = $w - $detailW
                $listTop = 4
                $listBottom = $h - 1
                $listHeight = $listBottom - $listTop + 1
                if ($listHeight -lt 1) { $listHeight = 1 }

                if ($view.Count -gt 0) {
                    if ($selected -lt $scroll) { $scroll = $selected }
                    if ($selected -ge ($scroll + $listHeight)) { $scroll = $selected - $listHeight + 1 }
                    if ($scroll -lt 0) { $scroll = 0 }
                }

                $nameWidth = 12
                if ($view.Count -gt 0) {
                    $nameWidth = [Math]::Max(12, ($view | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
                }

                $hline = [char]0x2500
                $vline = [char]0x2502
                $tl = [char]0x256D
                $tr = [char]0x256E
                $bl = [char]0x2570
                $br = [char]0x256F
                $ml = [char]0x251C
                $mr = [char]0x2524
                $tm = [char]0x252C
                $bm = [char]0x2534

                $lines = New-Object System.Collections.Generic.List[string]
                $innerW = $w - 2

                $title = ' SSH Connect '
                $topFill = $innerW - $title.Length
                if ($topFill -lt 0) { $topFill = 0 }
                $lines.Add("$sgrBorder$tl$($hline)$sgrTitle$title$sgrBorder$($hline.ToString() * $topFill)$tr$reset")

                $searchLabel = ' Search '
                $ghost = 'type to filter'
                $shownQuery = $queryText
                $searchRoom = $innerW - $searchLabel.Length - 1
                if ($shownQuery.Length -gt $searchRoom) {
                    $shownQuery = $shownQuery.Substring($shownQuery.Length - $searchRoom)
                }
                $searchBody = if ($shownQuery) {
                    "$sgrSearch$($shownQuery)$sgrAccent" + '_'
                }
                else {
                    "$sgrGhost$ghost"
                }
                $searchPlainLen = if ($shownQuery) { $shownQuery.Length + 1 } else { $ghost.Length }
                $searchPad = $innerW - $searchLabel.Length - $searchPlainLen
                if ($searchPad -lt 0) { $searchPad = 0 }
                $lines.Add("$sgrBorder$vline$sgrSearch$searchLabel$searchBody$sgrBg$(' ' * $searchPad)$sgrBorder$vline$reset")

                if ($showDetails) {
                    $leftInner = $listW - 2
                    $rightInner = $detailW - 2
                    $leftLabel = Limit-SshcText " Hosts ($($view.Count)/$($Entries.Count)) " $leftInner
                    $rightLabel = Limit-SshcText ' Details ' $rightInner
                    $lines.Add("$sgrBorder$ml$($hline)$sgrLabel$($leftLabel.TrimEnd())$sgrBorder$($hline.ToString() * ($leftInner - $leftLabel.TrimEnd().Length))$tm$($hline)$sgrTitle$($rightLabel.TrimEnd())$sgrBorder$($hline.ToString() * ($rightInner - $rightLabel.TrimEnd().Length))$mr$reset")
                }
                else {
                    $label = Limit-SshcText " Hosts ($($view.Count)/$($Entries.Count)) " $innerW
                    $lines.Add("$sgrBorder$ml$($hline)$sgrLabel$($label.TrimEnd())$sgrBorder$($hline.ToString() * ($innerW - $label.TrimEnd().Length))$mr$reset")
                }

                $detailLines = @()
                $currentEntry = $null
                if ($view.Count -gt 0) { $currentEntry = $view[$selected] }
                if ($currentEntry) {
                    $detailLines = @(
                        " HOST      $($currentEntry.Name)"
                        " USER      $(if ($currentEntry.User) { $currentEntry.User } else { '-' })"
                        " ADDRESS   $(if ($currentEntry.HostName) { $currentEntry.HostName } else { '-' })"
                        " PORT      $(if ($currentEntry.Port) { $currentEntry.Port } else { '22' })"
                        " KEY       $(if ($currentEntry.IdentityFile) { Split-Path $currentEntry.IdentityFile -Leaf } else { '-' })"
                        " JUMP      $(if ($currentEntry.ProxyJump) { $currentEntry.ProxyJump } else { '-' })"
                        " TUNNEL    $(if ($currentEntry.LocalForward) { $currentEntry.LocalForward } else { '-' })"
                    )
                    if ($currentEntry.Note) { $detailLines += " NOTE      $($currentEntry.Note)" }
                }

                for ($row = 0; $row -lt $listHeight; $row++) {
                    $idx = $scroll + $row
                    $leftInner = if ($showDetails) { $listW - 2 } else { $innerW }
                    $rightInner = $detailW - 2

                    $leftText = ''
                    $leftStyle = $sgrItem
                    if ($view.Count -eq 0 -and $row -eq 0) {
                        $leftText = Limit-SshcText '  no matches' $leftInner
                        $leftStyle = $sgrDim
                    }
                    elseif ($idx -lt $view.Count) {
                        $entry = $view[$idx]
                        $mark = if ($idx -eq $selected) { $pointer } else { ' ' }
                        $tags = @()
                        if ($entry.ProxyJump) { $tags += "via $($entry.ProxyJump)" }
                        if ($entry.LocalForward) { $tags += 'tunnel' }
                        $tagText = if ($tags) { '  ' + ($tags -join '  ') } else { '' }
                        $plain = '{0} {1}  {2}{3}' -f $mark, $entry.Name.PadRight($nameWidth), (Get-SshcTarget $entry), $tagText
                        $leftText = Limit-SshcText " $plain" $leftInner
                        $leftStyle = if ($idx -eq $selected) { $sgrSel } else { $sgrItem }
                    }
                    else {
                        $leftText = ' ' * $leftInner
                    }

                    if ($showDetails) {
                        $detailText = if ($row -lt $detailLines.Count) { $detailLines[$row] } else { '' }
                        $rightText = Limit-SshcText $detailText $rightInner
                        $rightStyle = if ($row -lt $detailLines.Count) { $sgrItem } else { $sgrBg }
                        $lines.Add("$sgrBorder$vline$leftStyle$leftText$sgrBorder$vline$rightStyle$rightText$sgrBorder$vline$reset")
                    }
                    else {
                        $lines.Add("$sgrBorder$vline$leftStyle$leftText$sgrBorder$vline$reset")
                    }
                }

                $hint = ' click/enter connect  ·  esc cancel  ·  ctrl-e edit  ·  type to filter '
                $hint = Limit-SshcText $hint $innerW
                if ($showDetails) {
                    $leftInner = $listW - 2
                    $rightInner = $detailW - 2
                    $lines.Add("$sgrBorder$bl$($hline.ToString() * $leftInner)$bm$($hline.ToString() * $rightInner)$br$reset")
                }
                else {
                    $lines.Add("$sgrBorder$bl$($hline.ToString() * $innerW)$br$reset")
                }

                # Footer overwrites the last border line if the window is tight; keep hints on the bottom border row by replacing it when height allows.
                if ($h -gt 10) {
                    $lines[$lines.Count - 1] = "$sgrBorder$bl$sgrDim$hint$sgrBorder$br$reset"
                }

                $frame = "$esc[H$esc[J" + ($lines -join "`n")
                [Console]::Write($frame)

                $layout = @{
                    ListTop    = $listTop
                    ListBottom = $listBottom
                    ListLeft   = 2
                    ListRight  = $listW - 1
                    ListHeight = $listHeight
                }

                $input = Read-SshcTuiInput
                switch ($input.Type) {
                    'cancel' { return $null }
                    'enter' {
                        if ($view.Count -gt 0) { return $view[$selected] }
                    }
                    'up' { $selected-- }
                    'down' { $selected++ }
                    'pageup' { $selected -= $layout.ListHeight }
                    'pagedown' { $selected += $layout.ListHeight }
                    'home' { $selected = 0 }
                    'end' { $selected = [Math]::Max(0, $view.Count - 1) }
                    'backspace' {
                        if ($queryText.Length -gt 0) {
                            $queryText = $queryText.Substring(0, $queryText.Length - 1)
                            $selected = 0
                            $scroll = 0
                        }
                    }
                    'clear' {
                        $queryText = ''
                        $selected = 0
                        $scroll = 0
                    }
                    'char' {
                        $queryText += $input.Char
                        $selected = 0
                        $scroll = 0
                    }
                    'edit' {
                        if ($ConfigPath) { code $ConfigPath }
                    }
                    'mouse' {
                        if (-not $input.Down) { break }
                        if ($input.Button -eq 64) { $selected--; break }
                        if ($input.Button -eq 65) { $selected++; break }
                        if ($input.Button -ne 0) { break }
                        if ($input.Y -ge $layout.ListTop -and $input.Y -le $layout.ListBottom -and
                            $input.X -ge $layout.ListLeft -and $input.X -le $layout.ListRight) {
                            $idx = $scroll + ($input.Y - $layout.ListTop)
                            if ($idx -ge 0 -and $idx -lt $view.Count) {
                                $now = [datetime]::UtcNow
                                if ($idx -eq $lastClickIndex -and ($now - $lastClickAt).TotalMilliseconds -lt 450) {
                                    return $view[$idx]
                                }
                                $selected = $idx
                                $lastClickIndex = $idx
                                $lastClickAt = $now
                            }
                        }
                    }
                }
            }
        }
        finally {
            [Console]::Write("$esc[?1002l$esc[?1006l$esc[?1000l$esc[?7h$esc[?25h$esc[?1049l")
            [Console]::CursorVisible = $savedCursor
            [Console]::TreatControlCAsInput = $savedTreatCtrlC
            [Console]::OutputEncoding = $savedOutputEncoding
            if ($hasSavedMode) {
                [void][SshcNativeConsole]::SetConsoleMode($inputHandle, $savedMode)
            }
        }
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

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        $picked = Show-SshcFallbackMenu $entries
        if ($picked) { Connect-SshcHost $picked }
        return
    }

    $picked = Show-SshcTui -Entries $entries -Query $Filter -ConfigPath $configPath
    if ($picked) { Connect-SshcHost $picked }
}

Register-ArgumentCompleter -CommandName sshc -ParameterName Filter -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    sshls | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
