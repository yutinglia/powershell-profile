# Current-host profile. Fragments live in profile.d and load in filename order.
$ProfileDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $profile }
$ProfileFragments = Join-Path $ProfileDir 'profile.d'

Get-ChildItem -Path $ProfileFragments -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Sort-Object Name |
    ForEach-Object {
        try {
            . $_.FullName
        }
        catch {
            Write-Host "Failed to load profile fragment '$($_.Name)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
