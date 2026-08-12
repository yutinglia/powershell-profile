# Install profile dependencies. Oh My Posh is installed with winget (user scope).
$ErrorActionPreference = 'Stop'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error 'winget is required. Install "App Installer" from the Microsoft Store.'
}

Write-Host 'Installing Oh My Posh with winget...'
winget install --id JanDeDobbeleer.OhMyPosh --exact --source winget --scope user --force --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0) {
    Write-Error "winget install failed with exit code $LASTEXITCODE"
}

$secrets = Join-Path $PSScriptRoot 'profile.d\01-secrets.ps1'
$example = Join-Path $PSScriptRoot 'profile.d\01-secrets.example.ps1'
if (-not (Test-Path -LiteralPath $secrets) -and (Test-Path -LiteralPath $example)) {
    Copy-Item -LiteralPath $example -Destination $secrets
    Write-Host 'Created profile.d/01-secrets.ps1 from the example. Fill in your keys.'
}

Write-Host 'Done. Open a new terminal so PATH and the prompt pick up Oh My Posh.'
