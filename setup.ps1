# Install dependencies this PowerShell profile needs to load and run.
param(
    [switch]$Optional
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -ne 'Core') {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        & $pwsh.Source -NoProfile -File $PSCommandPath @PSBoundParameters
        exit $LASTEXITCODE
    }
}

function Install-ProfileWingetPackage {
    param([Parameter(Mandatory)][string]$Id)

    Write-Host "winget: $Id"
    winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Write-Warning "winget install $Id exited with code $LASTEXITCODE"
    }
}

function Install-ProfileModule {
    param([Parameter(Mandatory)][string]$Name)

    if (Get-Module -ListAvailable -Name $Name) {
        Write-Host "module already installed: $Name"
        return
    }

    Write-Host "Install-Module: $Name"
    Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error 'winget is required. Install "App Installer" from the Microsoft Store.'
}

# Required: prompt, git status in prompt, editor helpers, GitHub Copilot helpers.
$wingetRequired = @(
    'Microsoft.PowerShell',
    'JanDeDobbeleer.OhMyPosh',
    'Git.Git',
    'GitHub.cli',
    'Microsoft.VisualStudioCode'
)

# Used by aliases (nx/pm/wezconf) or optional AllHosts tools; not required to load the profile.
$wingetOptional = @(
    'wez.wezterm',
    'Anaconda.Miniconda3',
    'CoreyButler.NVMforWindows'
)

Write-Host 'Installing winget packages...'
foreach ($id in $wingetRequired) {
    Install-ProfileWingetPackage -Id $id
}

if ($Optional) {
    Write-Host 'Installing optional winget packages...'
    foreach ($id in $wingetOptional) {
        Install-ProfileWingetPackage -Id $id
    }
}

Write-Host 'Installing PowerShell modules from PSGallery...'
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
}
Install-ProfileModule -Name Terminal-Icons
Install-ProfileModule -Name posh-git

$omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
if ($omp) {
    $nerdFonts = @(
        'MesloLGS Nerd Font'
        'MesloLGS Nerd Font Mono'
        'MesloLGM Nerd Font'
        'CaskaydiaCove Nerd Font'
    )
    $installedFonts = @()
    try {
        $installedFonts = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name
    }
    catch {
        Add-Type -AssemblyName System.Drawing
        $installedFonts = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name
    }

    $hasNerdFont = $false
    foreach ($name in $nerdFonts) {
        if ($installedFonts -contains $name) { $hasNerdFont = $true; break }
    }

    if (-not $hasNerdFont) {
        Write-Host 'Installing Meslo Nerd Font via Oh My Posh...'
        & $omp.Source font install Meslo
    }
    else {
        Write-Host 'Nerd Font already installed.'
    }
}

$secrets = Join-Path $PSScriptRoot 'profile.d\01-secrets.ps1'
$example = Join-Path $PSScriptRoot 'profile.d\01-secrets.example.ps1'
if (-not (Test-Path -LiteralPath $secrets) -and (Test-Path -LiteralPath $example)) {
    Copy-Item -LiteralPath $example -Destination $secrets
    Write-Host 'Created profile.d/01-secrets.ps1 from the example. Fill in your keys.'
}

Write-Host 'Done. Open a new terminal so PATH and the prompt pick up new tools.'
