function Invoke-ProfilePicker {
    <#
    .SYNOPSIS
        Interactive native TUI picker with a numbered fallback menu.
    .DESCRIPTION
        Opens an alt-screen Dracula picker (mouse, hover, dirty redraw). When stdin or stdout
        is redirected, uses a numbered menu instead. Returns the selected item, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,

        [string]$Title = ' Picker ',
        [string]$ListLabel = 'Items',
        [string]$Query = '',
        [string]$Hint = ' click/enter select  ·  esc cancel  ·  type to filter ',
        [string]$FallbackPrompt = 'Select number (or q to cancel)',

        [scriptblock]$Filter,
        [scriptblock]$FormatRow,
        [scriptblock]$FormatDetails,
        [scriptblock]$FormatFallback,
        [hashtable]$OnKey
    )

    function ConvertTo-ProfileTuiRgb {
        param([string]$Hex)
        @(
            [Convert]::ToInt32($Hex.Substring(1, 2), 16)
            [Convert]::ToInt32($Hex.Substring(3, 2), 16)
            [Convert]::ToInt32($Hex.Substring(5, 2), 16)
        )
    }

    function Get-ProfileTuiSgr {
        param([string]$Fg, [string]$Bg, [switch]$Bold)
        $parts = @()
        if ($Bold) { $parts += '1' }
        if ($Fg) {
            $rgb = ConvertTo-ProfileTuiRgb $Fg
            $parts += "38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
        }
        if ($Bg) {
            $rgb = ConvertTo-ProfileTuiRgb $Bg
            $parts += "48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])"
        }
        "$([char]27)[$($parts -join ';')m"
    }

    function Limit-ProfileTuiText {
        param([string]$Text, [int]$Width)
        if ($Width -le 0) { return '' }
        if ($null -eq $Text) { $Text = '' }
        if ($Text.Length -le $Width) { return $Text.PadRight($Width) }
        if ($Width -eq 1) { return $Text.Substring(0, 1) }
        return $Text.Substring(0, $Width - 1) + [char]0x2026
    }

    function Initialize-ProfileTuiNativeConsole {
        if ('ProfileTuiNativeConsole' -as [type]) { return }
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ProfileTuiNativeConsole {
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

    function Read-ProfileTuiInput {
        $k = [Console]::ReadKey($true)
        $ctrl = [ConsoleModifiers]::Control

        # VT_INPUT often strips ConsoleModifiers and delivers C0 bytes (Ctrl+A = 1 … Ctrl+Z = 26).
        $ctrlChar = [int][char]$k.KeyChar
        $withCtrl = [bool]($k.Modifiers -band $ctrl)
        $ctrlLetter = $null
        if ($ctrlChar -ge 1 -and $ctrlChar -le 26) {
            $ctrlLetter = [string][char](64 + $ctrlChar)
        }
        elseif ($withCtrl -and $k.Key -ge [ConsoleKey]::A -and $k.Key -le [ConsoleKey]::Z) {
            $ctrlLetter = $k.Key.ToString()
        }

        if ($ctrlLetter -eq 'C') { return @{ Type = 'cancel' } }
        if ($ctrlLetter -eq 'U') { return @{ Type = 'clear' } }

        # VT_INPUT / Windows Terminal often delivers Backspace as DEL (0x7F) or BS (0x08)
        # instead of ConsoleKey.Backspace; both are control chars and were previously ignored.
        if (
            $k.Key -eq [ConsoleKey]::Backspace -or
            $k.Key -eq [ConsoleKey]::Delete -or
            $k.KeyChar -eq [char]8 -or
            $k.KeyChar -eq [char]127
        ) {
            return @{ Type = 'backspace' }
        }

        switch ($k.Key) {
            ([ConsoleKey]::Enter) { return @{ Type = 'enter' } }
            ([ConsoleKey]::UpArrow) { return @{ Type = 'up' } }
            ([ConsoleKey]::DownArrow) { return @{ Type = 'down' } }
            ([ConsoleKey]::PageUp) { return @{ Type = 'pageup' } }
            ([ConsoleKey]::PageDown) { return @{ Type = 'pagedown' } }
            ([ConsoleKey]::Home) { return @{ Type = 'home' } }
            ([ConsoleKey]::End) { return @{ Type = 'end' } }
            ([ConsoleKey]::Tab) { return @{ Type = 'down' } }
        }

        $isEsc = ($k.Key -eq [ConsoleKey]::Escape) -or ($k.KeyChar -eq [char]27)
        if ($isEsc) {
            $seq = [System.Text.StringBuilder]::new()
            [void]$seq.Append([char]27)
            $mouseRe = [char]27 + '\[<(\d+);(\d+);(\d+)([Mm])'
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 25 -and -not [Console]::KeyAvailable) { }
            if (-not [Console]::KeyAvailable) {
                return @{ Type = 'cancel' }
            }

            $next = [Console]::ReadKey($true)
            [void]$seq.Append($next.KeyChar)

            if ($next.KeyChar -eq '[') {
                $sw.Restart()
                while ($sw.ElapsedMilliseconds -lt 8 -and -not [Console]::KeyAvailable) { }
                if ([Console]::KeyAvailable) {
                    $next = [Console]::ReadKey($true)
                    [void]$seq.Append($next.KeyChar)
                    if ($next.KeyChar -eq '<') {
                        $limit = 512
                        $n = 0
                        $sw.Restart()
                        while ($n -lt $limit) {
                            if ($seq.ToString() -match $mouseRe) {
                                while ([Console]::KeyAvailable -and $n -lt $limit) {
                                    $ch = [Console]::ReadKey($true)
                                    [void]$seq.Append($ch.KeyChar)
                                    $n++
                                }
                                break
                            }
                            if ([Console]::KeyAvailable) {
                                $ch = [Console]::ReadKey($true)
                                [void]$seq.Append($ch.KeyChar)
                                $n++
                                $sw.Restart()
                                continue
                            }
                            if ($sw.ElapsedMilliseconds -ge 20) { break }
                        }

                        $mouseMatches = [regex]::Matches($seq.ToString(), $mouseRe)
                        if ($mouseMatches.Count -gt 0) {
                            $mouse = $mouseMatches[$mouseMatches.Count - 1]
                            return @{
                                Type   = 'mouse'
                                Button = [int]$mouse.Groups[1].Value
                                X      = [int]$mouse.Groups[2].Value
                                Y      = [int]$mouse.Groups[3].Value
                                Down   = $mouse.Groups[4].Value -eq 'M'
                            }
                        }
                        return @{ Type = 'none' }
                    }
                }
            }

            $waitMs = 8
            $sw.Restart()
            while ($sw.ElapsedMilliseconds -lt $waitMs) {
                if ([Console]::KeyAvailable) {
                    $next = [Console]::ReadKey($true)
                    [void]$seq.Append($next.KeyChar)
                    $sw.Restart()
                }
            }
            $s = $seq.ToString()
            if ($s.Length -eq 1) { return @{ Type = 'cancel' } }
            if ($s.Contains([char]27 + '[A')) { return @{ Type = 'up' } }
            if ($s.Contains([char]27 + '[B')) { return @{ Type = 'down' } }
            if ($s.Contains([char]27 + '[3~')) { return @{ Type = 'backspace' } }
            if ($s.Contains([char]27 + '[5~')) { return @{ Type = 'pageup' } }
            if ($s.Contains([char]27 + '[6~')) { return @{ Type = 'pagedown' } }
            return @{ Type = 'none' }
        }

        if ($ctrlLetter) {
            return @{ Type = 'ctrl'; Key = $ctrlLetter }
        }

        if ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) {
            return @{ Type = 'char'; Char = [string]$k.KeyChar }
        }
        return @{ Type = 'none' }
    }

    function Show-ProfileTuiFallback {
        param($Entries)

        for ($i = 0; $i -lt $Entries.Count; $i++) {
            $line = & $FormatFallback $Entries[$i]
            Write-Host ('  [{0}] {1}' -f ($i + 1), $line)
        }
        while ($true) {
            $choice = Read-Host $FallbackPrompt
            if ($choice -eq 'q') { Write-Host 'Cancelled.'; return $null }
            if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Entries.Count) {
                return $Entries[[int]$choice - 1]
            }
            Write-Host "Invalid selection. Enter 1-$($Entries.Count), or q to cancel."
        }
    }

    function Show-ProfileTui {
        param(
            $Entries,
            [string]$QueryText
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
        $sgrBg = Get-ProfileTuiSgr -Fg $fg -Bg $bg
        $sgrBorder = Get-ProfileTuiSgr -Fg $comment -Bg $bg
        $sgrTitle = Get-ProfileTuiSgr -Fg $purple -Bg $bg -Bold
        $sgrSearch = Get-ProfileTuiSgr -Fg $cyan -Bg $bg
        $sgrGhost = Get-ProfileTuiSgr -Fg $comment -Bg $bg
        $sgrSel = Get-ProfileTuiSgr -Fg $green -Bg $current -Bold
        $sgrItem = Get-ProfileTuiSgr -Fg $fg -Bg $bg
        $sgrDim = Get-ProfileTuiSgr -Fg $comment -Bg $bg
        $sgrAccent = Get-ProfileTuiSgr -Fg $pink -Bg $bg
        $sgrLabel = Get-ProfileTuiSgr -Fg $green -Bg $bg
        $pointer = [char]0x25B6

        $queryText = if ($QueryText) { $QueryText } else { '' }
        $selected = 0
        $scroll = 0
        $lastClickIndex = -1
        $lastClickAt = [datetime]::MinValue
        $dirty = $true
        $lastW = -1
        $lastH = -1

        Initialize-ProfileTuiNativeConsole
        $inputHandle = [ProfileTuiNativeConsole]::GetStdHandle(-10)
        $savedMode = [uint32]0
        $hasSavedMode = [ProfileTuiNativeConsole]::GetConsoleMode($inputHandle, [ref]$savedMode)
        if ($hasSavedMode) {
            $newMode = $savedMode
            $newMode = $newMode -bor [uint32]0x0080  # EXTENDED_FLAGS
            $newMode = $newMode -bor [uint32]0x0010  # MOUSE_INPUT
            $newMode = $newMode -bor [uint32]0x0200  # VT_INPUT
            $newMode = $newMode -band (-bnot [uint32]0x0040)  # ~QUICK_EDIT
            $newMode = $newMode -band (-bnot [uint32]0x0002)  # ~LINE_INPUT
            $newMode = $newMode -band (-bnot [uint32]0x0004)  # ~ECHO_INPUT
            [void][ProfileTuiNativeConsole]::SetConsoleMode($inputHandle, $newMode)
        }

        $savedTreatCtrlC = [Console]::TreatControlCAsInput
        $savedCursor = [Console]::CursorVisible
        $savedOutputEncoding = [Console]::OutputEncoding
        try {
            [Console]::TreatControlCAsInput = $true
            [Console]::CursorVisible = $false
            [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
            [Console]::Write("$esc[?1049h$esc[?25l$esc[?7l$esc[?1000h$esc[?1006h$esc[?1003h")

            while ($true) {
                $view = @($Entries)
                if ($queryText) {
                    $view = @(foreach ($entry in $Entries) {
                        if (& $Filter $entry $queryText) { $entry }
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
                if ($w -ne $lastW -or $h -ne $lastH) {
                    $dirty = $true
                    $lastW = $w
                    $lastH = $h
                }

                $showDetails = $w -ge 72 -and $null -ne $FormatDetails
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

                $layout = @{
                    ListTop    = $listTop
                    ListBottom = $listBottom
                    ListLeft   = 2
                    ListRight  = $listW - 1
                    ListHeight = $listHeight
                }

                if ($dirty) {
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

                $topFill = $innerW - $Title.Length
                if ($topFill -lt 0) { $topFill = 0 }
                $lines.Add("$sgrBorder$tl$($hline)$sgrTitle$Title$sgrBorder$($hline.ToString() * $topFill)$tr$reset")

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

                $countLabel = " $ListLabel ($($view.Count)/$($Entries.Count)) "
                if ($showDetails) {
                    $leftInner = $listW - 2
                    $rightInner = $detailW - 2
                    $leftLabel = Limit-ProfileTuiText $countLabel $leftInner
                    $rightLabel = Limit-ProfileTuiText ' Details ' $rightInner
                    $lines.Add("$sgrBorder$ml$($hline)$sgrLabel$($leftLabel.TrimEnd())$sgrBorder$($hline.ToString() * ($leftInner - $leftLabel.TrimEnd().Length))$tm$($hline)$sgrTitle$($rightLabel.TrimEnd())$sgrBorder$($hline.ToString() * ($rightInner - $rightLabel.TrimEnd().Length))$mr$reset")
                }
                else {
                    $label = Limit-ProfileTuiText $countLabel $innerW
                    $lines.Add("$sgrBorder$ml$($hline)$sgrLabel$($label.TrimEnd())$sgrBorder$($hline.ToString() * ($innerW - $label.TrimEnd().Length))$mr$reset")
                }

                $detailLines = @()
                $currentEntry = $null
                if ($view.Count -gt 0) { $currentEntry = $view[$selected] }
                if ($currentEntry -and $FormatDetails) {
                    $detailLines = @(& $FormatDetails $currentEntry)
                }

                for ($row = 0; $row -lt $listHeight; $row++) {
                    $idx = $scroll + $row
                    $leftInner = if ($showDetails) { $listW - 2 } else { $innerW }
                    $rightInner = $detailW - 2

                    $leftText = ''
                    $leftStyle = $sgrItem
                    if ($view.Count -eq 0 -and $row -eq 0) {
                        $leftText = Limit-ProfileTuiText '  no matches' $leftInner
                        $leftStyle = $sgrDim
                    }
                    elseif ($idx -lt $view.Count) {
                        $entry = $view[$idx]
                        $mark = if ($idx -eq $selected) { $pointer } else { ' ' }
                        $rowBody = & $FormatRow $entry
                        if ($null -eq $rowBody) { $rowBody = '' }
                        $plain = '{0} {1}' -f $mark, $rowBody
                        $leftText = Limit-ProfileTuiText " $plain" $leftInner
                        $leftStyle = if ($idx -eq $selected) { $sgrSel } else { $sgrItem }
                    }
                    else {
                        $leftText = ' ' * $leftInner
                    }

                    if ($showDetails) {
                        $detailText = if ($row -lt $detailLines.Count) { $detailLines[$row] } else { '' }
                        $rightText = Limit-ProfileTuiText $detailText $rightInner
                        $rightStyle = if ($row -lt $detailLines.Count) { $sgrItem } else { $sgrBg }
                        $lines.Add("$sgrBorder$vline$leftStyle$leftText$sgrBorder$vline$rightStyle$rightText$sgrBorder$vline$reset")
                    }
                    else {
                        $lines.Add("$sgrBorder$vline$leftStyle$leftText$sgrBorder$vline$reset")
                    }
                }

                $hintText = Limit-ProfileTuiText $Hint $innerW
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
                    $lines[$lines.Count - 1] = "$sgrBorder$bl$sgrDim$hintText$sgrBorder$br$reset"
                }

                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.Append("$esc[?2026h")
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    [void]$sb.Append("$esc[$($i + 1);1H")
                    [void]$sb.Append($lines[$i])
                    [void]$sb.Append("$sgrBg$esc[K")
                }
                if ($lines.Count -lt $h) {
                    [void]$sb.Append("$esc[$($lines.Count + 1);1H$sgrBg$esc[J")
                }
                [void]$sb.Append("$esc[?2026l")
                [Console]::Write($sb.ToString())
                $dirty = $false
                }

                $tuiInput = Read-ProfileTuiInput
                switch ($tuiInput.Type) {
                    'cancel' { return $null }
                    'enter' {
                        if ($view.Count -gt 0) { return $view[$selected] }
                    }
                    'up' { $selected--; $dirty = $true }
                    'down' { $selected++; $dirty = $true }
                    'pageup' { $selected -= $layout.ListHeight; $dirty = $true }
                    'pagedown' { $selected += $layout.ListHeight; $dirty = $true }
                    'home' { $selected = 0; $dirty = $true }
                    'end' { $selected = [Math]::Max(0, $view.Count - 1); $dirty = $true }
                    'backspace' {
                        if ($queryText.Length -gt 0) {
                            $queryText = $queryText.Substring(0, $queryText.Length - 1)
                            $selected = 0
                            $scroll = 0
                            $dirty = $true
                        }
                    }
                    'clear' {
                        $queryText = ''
                        $selected = 0
                        $scroll = 0
                        $dirty = $true
                    }
                    'char' {
                        $queryText += $tuiInput.Char
                        $selected = 0
                        $scroll = 0
                        $dirty = $true
                    }
                    'ctrl' {
                        if ($OnKey -and $tuiInput.Key) {
                            $handler = $OnKey[$tuiInput.Key]
                            if ($handler) {
                                $current = if ($view.Count -gt 0) { $view[$selected] } else { $null }
                                & $handler $current
                                $dirty = $true
                            }
                        }
                    }
                    'mouse' {
                        $inList = $tuiInput.Y -ge $layout.ListTop -and $tuiInput.Y -le $layout.ListBottom -and
                            $tuiInput.X -ge $layout.ListLeft -and $tuiInput.X -le $layout.ListRight
                        $idx = $scroll + ($tuiInput.Y - $layout.ListTop)
                        $validIdx = $inList -and $idx -ge 0 -and $idx -lt $view.Count

                        if ($tuiInput.Button -eq 35 -or $tuiInput.Button -eq 32) {
                            if ($validIdx -and $idx -ne $selected) {
                                $selected = $idx
                                $dirty = $true
                            }
                            break
                        }
                        if (-not $tuiInput.Down) { break }
                        if ($tuiInput.Button -eq 64) { $selected--; $dirty = $true; break }
                        if ($tuiInput.Button -eq 65) { $selected++; $dirty = $true; break }
                        if ($tuiInput.Button -ne 0) { break }
                        if ($validIdx) {
                            $now = [datetime]::UtcNow
                            if ($idx -eq $lastClickIndex -and ($now - $lastClickAt).TotalMilliseconds -lt 450) {
                                return $view[$idx]
                            }
                            $selected = $idx
                            $lastClickIndex = $idx
                            $lastClickAt = $now
                            $dirty = $true
                        }
                    }
                }
            }
        }
        finally {
            [Console]::Write("$esc[?2026l$esc[?1003l$esc[?1006l$esc[?1000l$esc[?7h$esc[?25h$esc[?1049l")
            [Console]::CursorVisible = $savedCursor
            [Console]::TreatControlCAsInput = $savedTreatCtrlC
            [Console]::OutputEncoding = $savedOutputEncoding
            if ($hasSavedMode) {
                [void][ProfileTuiNativeConsole]::SetConsoleMode($inputHandle, $savedMode)
            }
        }
    }

    if (-not $Filter) {
        $Filter = {
            param($item, $query)
            if ($null -ne $item.PSObject.Properties['Name'] -and $null -ne $item.Name) {
                return [string]$item.Name -like "*$query*"
            }
            return "$item" -like "*$query*"
        }
    }
    if (-not $FormatRow) {
        $FormatRow = {
            param($item)
            if ($null -ne $item.PSObject.Properties['Name'] -and $null -ne $item.Name) {
                return [string]$item.Name
            }
            return "$item"
        }
    }
    if (-not $FormatFallback) {
        $FormatFallback = $FormatRow
    }
    if (-not $OnKey) {
        $OnKey = @{}
    }

    $Items = @($Items)
    if ($Items.Count -eq 0) {
        return $null
    }

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        return (Show-ProfileTuiFallback -Entries $Items)
    }

    return (Show-ProfileTui -Entries $Items -QueryText $Query)
}
