$ompTheme = Join-Path (Split-Path $PSScriptRoot -Parent) 'themes\my-theme.omp.json'
$ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
if (-not $ompCmd) {
    Write-Host 'Oh My Posh is not installed. Run .\setup.ps1' -ForegroundColor Yellow
}
elseif (-not (Test-Path -LiteralPath $ompTheme)) {
    Write-Host "Oh My Posh theme not found: $ompTheme" -ForegroundColor Yellow
}
else {
    $ompCacheDir = Join-Path $env:LOCALAPPDATA 'pwsh-profile'
    $ompCache = Join-Path $ompCacheDir 'omp-init.ps1'
    $ompExe = $ompCmd.Source
    $ompNeed = -not (Test-Path -LiteralPath $ompCache)
    if (-not $ompNeed) {
        $ompCacheTime = (Get-Item -LiteralPath $ompCache).LastWriteTimeUtc
        if ($ompCacheTime -lt (Get-Item -LiteralPath $ompTheme).LastWriteTimeUtc) {
            $ompNeed = $true
        }
        elseif ($ompExe -and (Test-Path -LiteralPath $ompExe) -and $ompCacheTime -lt (Get-Item -LiteralPath $ompExe).LastWriteTimeUtc) {
            $ompNeed = $true
        }
    }
    if ($ompNeed) {
        New-Item -ItemType Directory -Path $ompCacheDir -Force | Out-Null
        $ompScript = oh-my-posh init pwsh --config $ompTheme | Out-String
        if ($ompScript -and $ompScript.Trim()) {
            Set-Content -LiteralPath $ompCache -Value $ompScript -Encoding utf8
        }
    }
    if (Test-Path -LiteralPath $ompCache) {
        . $ompCache
    }
    else {
        oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
    }
}
