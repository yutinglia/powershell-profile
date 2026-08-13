# Current-host profile. Fragments live in profile.d and load in filename order.
# Non-interactive one-shots skip fragments. *.lazy.ps1 loads on first use via 00-lazy.ps1.
$ProfileDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $profile }
$ProfileFragments = Join-Path $ProfileDir 'profile.d'

if (-not [Environment]::UserInteractive) { return }

$profileNoExit = $false
$profileOneShot = $false
foreach ($profileArg in [Environment]::GetCommandLineArgs()) {
    if ($profileArg -match '^-{1,2}NoE(xit)?$') { $profileNoExit = $true }
    elseif ($profileArg -match '^-{1,2}NonI(nteractive)?$') { $profileOneShot = $true }
    elseif ($profileArg -match '^-{1,2}(c|Command|f|File|e|ec|EncodedCommand)$') { $profileOneShot = $true }
}
if ($profileOneShot -and -not $profileNoExit) { return }
Remove-Variable profileNoExit, profileOneShot, profileArg -ErrorAction SilentlyContinue

Get-ChildItem -Path $ProfileFragments -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '*.lazy.ps1' -and $_.Name -notlike '*.example.ps1' } |
    Sort-Object Name |
    ForEach-Object {
        $profileFragment = $_
        try {
            . $profileFragment.FullName
        }
        catch {
            Write-Host "Failed to load profile fragment '$($profileFragment.Name)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }

if (Get-Command Register-ProfileLazyFunction -ErrorAction SilentlyContinue) {
    Register-ProfileLazyFunction -Command Get-ChildItem -File '12-terminal-icons.lazy.ps1'
}
