function help {
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
        Select-String -LiteralPath $file.FullName -Pattern '^function\s+([a-zA-Z0-9_.-]+)' | ForEach-Object {
            $rel = if ($file.DirectoryName -eq $fragmentDir) {
                "profile.d/$($file.Name)"
            }
            else {
                $file.Name
            }
            [pscustomobject]@{
                Name = $_.Matches.Groups[1].Value
                File = $rel
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
    foreach ($row in $rows) {
        Write-Host ('  {0}  ' -f $row.Name.PadRight($nameWidth)) -NoNewline
        Write-Host $row.File -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host "Use 'pshelp' to display powershell help"
}

function pshelp {
    Get-Help @args
}
