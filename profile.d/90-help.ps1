function help {
    <#
    .SYNOPSIS
        List profile functions with a one-line description.
    #>

    function Get-ProfileHelpSynopsis {
        param(
            [string[]]$Lines,
            [int]$FunctionIndex
        )

        for ($j = $FunctionIndex + 1; $j -lt $Lines.Count; $j++) {
            $trim = $Lines[$j].Trim()
            if ($trim -eq '') {
                continue
            }
            if ($trim -eq '{' -or $trim -eq '<#' -or $trim.StartsWith('<#')) {
                if ($trim -eq '{') {
                    continue
                }

                $inSynopsis = $false
                $start = if ($trim -eq '<#') { $j + 1 } else { $j }
                for ($k = $start; $k -lt $Lines.Count; $k++) {
                    $helpLine = $Lines[$k].Trim()
                    if ($helpLine -eq '#>' -or $helpLine.EndsWith('#>')) {
                        break
                    }
                    if ($helpLine -eq '.SYNOPSIS') {
                        $inSynopsis = $true
                        continue
                    }
                    if ($inSynopsis) {
                        if ($helpLine.StartsWith('.')) {
                            break
                        }
                        if ($helpLine) {
                            return $helpLine
                        }
                    }
                }
            }
            break
        }

        return ''
    }

    $profileDir = Split-Path -Parent $profile
    $fragmentDir = Join-Path $profileDir 'profile.d'
    $files = @()
    if (Test-Path -LiteralPath $profile) {
        $files += Get-Item -LiteralPath $profile
    }
    if (Test-Path -LiteralPath $fragmentDir) {
        $files += Get-ChildItem -LiteralPath $fragmentDir -Filter '*.ps1' -File
    }

    $rows = foreach ($file in $files) {
        $lines = Get-Content -LiteralPath $file.FullName
        $rel = if ($file.DirectoryName -eq $fragmentDir) {
            "profile.d/$($file.Name)"
        }
        else {
            $file.Name
        }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^function\s+([a-zA-Z0-9_.-]+)') {
                [pscustomobject]@{
                    Name     = $Matches[1]
                    Synopsis = Get-ProfileHelpSynopsis -Lines $lines -FunctionIndex $i
                    File     = $rel
                }
            }
        }
    }

    $rows = @($rows | Sort-Object Name)
    Write-Host 'Profile functions:'
    Write-Host ''
    if ($rows.Count -eq 0) {
        Write-Host '  (none)'
        return
    }

    $nameWidth = ($rows | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $fileWidth = ($rows | ForEach-Object { $_.File.Length } | Measure-Object -Maximum).Maximum
    $maxSyn = ($rows | ForEach-Object { $_.Synopsis.Length } | Measure-Object -Maximum).Maximum

    $consoleWidth = 120
    try {
        if ([Console]::WindowWidth -gt 0) {
            $consoleWidth = [Console]::WindowWidth
        }
    }
    catch {
    }

    $synopsisBudget = $consoleWidth - 2 - $nameWidth - 2 - 2 - $fileWidth
    if ($synopsisBudget -lt 8) {
        $synopsisBudget = 8
    }
    $synWidth = [Math]::Min($maxSyn, $synopsisBudget)

    foreach ($row in $rows) {
        Write-Host ('  {0}  ' -f $row.Name.PadRight($nameWidth)) -NoNewline
        if ($synWidth -gt 0) {
            $syn = $row.Synopsis
            if ($syn.Length -gt $synWidth) {
                $keep = [Math]::Max(1, $synWidth - 1)
                $syn = $syn.Substring(0, $keep) + [char]0x2026
            }
            Write-Host ($syn.PadRight($synWidth) + '  ') -NoNewline -ForegroundColor DarkGray
        }
        Write-Host $row.File -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host "Use 'pshelp' to display powershell help"
}

function pshelp {
    <#
    .SYNOPSIS
        Show PowerShell help (Get-Help).
    #>
    Get-Help @args
}
