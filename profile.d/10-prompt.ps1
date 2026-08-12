Import-Module -Name Terminal-Icons
Import-Module posh-git

$ompTheme = Join-Path (Split-Path $PSScriptRoot -Parent) 'themes\my-theme.omp.json'
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host 'Oh My Posh is not installed. Run .\setup.ps1' -ForegroundColor Yellow
}
elseif (-not (Test-Path -LiteralPath $ompTheme)) {
    Write-Host "Oh My Posh theme not found: $ompTheme" -ForegroundColor Yellow
}
else {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}
