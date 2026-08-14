# Current-host profile. Fragments live in profile.d and load in filename order.
# Non-interactive one-shots skip fragments. *.lazy.ps1 loads on first use via 00-lazy.ps1.
$ProfileDir = if ($PSScriptRoot) { $PSScriptRoot } else { [System.IO.Path]::GetDirectoryName($profile) }
$ProfileFragments = [System.IO.Path]::Combine($ProfileDir, 'profile.d')

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

$profileFragmentPaths = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($profileFragmentPath in [System.IO.Directory]::EnumerateFiles(
        $ProfileFragments,
        '*.ps1',
        [System.IO.SearchOption]::TopDirectoryOnly
    )) {
        $profileFragmentName = [System.IO.Path]::GetFileName($profileFragmentPath)
        if (
            $profileFragmentName.EndsWith('.lazy.ps1', [System.StringComparison]::OrdinalIgnoreCase) -or
            $profileFragmentName.EndsWith('.example.ps1', [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            continue
        }
        $profileFragmentPaths.Add($profileFragmentPath)
    }
}
catch {
}

$profileFragmentPaths.Sort([System.StringComparer]::CurrentCultureIgnoreCase)
foreach ($profileFragmentPath in $profileFragmentPaths) {
    $profileFragment = [System.IO.FileInfo]::new($profileFragmentPath)
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
