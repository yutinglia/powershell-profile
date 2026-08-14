[CmdletBinding()]
param(
    [ValidateRange(0, 1000)]
    [int]$WarmupCount = 2,

    [ValidateRange(1, 10000)]
    [int]$SampleCount = 15,

    [ValidateNotNullOrEmpty()]
    [string]$PowerShellPath = 'pwsh'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$powerShellCommand = Get-Command -Name $PowerShellPath -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$powerShellExecutable = $powerShellCommand.Source

$cases = @(
    [pscustomobject]@{
        Name      = 'NoProfile'
        Arguments = @('-NoLogo', '-NoProfile', '-NoExit', '-Command', 'exit')
    }
    [pscustomobject]@{
        Name      = 'WithProfile'
        Arguments = @('-NoLogo', '-NoExit', '-Command', 'exit')
    }
)

function Invoke-StartupSample {
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Executable @ArgumentList *> $null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $stopwatch.Stop()
    }

    if ($exitCode -ne 0) {
        throw "PowerShell startup sample exited with code $exitCode."
    }

    $stopwatch.Elapsed.TotalMilliseconds
}

function Get-StartupStatistics {
    param(
        [Parameter(Mandatory)]
        [double[]]$Samples
    )

    $sorted = [double[]]@($Samples | Sort-Object)
    $middle = [Math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2) {
        $sorted[$middle]
    }
    else {
        ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }

    $sum = 0.0
    foreach ($sample in $Samples) {
        $sum += $sample
    }

    $p95Index = [Math]::Max(0, [Math]::Ceiling($sorted.Count * 0.95) - 1)
    [pscustomobject]@{
        MedianMs = $median
        MeanMs   = $sum / $Samples.Count
        P95Ms    = $sorted[$p95Index]
        MinMs    = $sorted[0]
        MaxMs    = $sorted[-1]
    }
}

$measurements = [ordered]@{}
foreach ($case in $cases) {
    $measurements[$case.Name] = [System.Collections.Generic.List[double]]::new()
}

for ($warmupIndex = 0; $warmupIndex -lt $WarmupCount; $warmupIndex++) {
    Write-Verbose "Warm-up $($warmupIndex + 1)/$WarmupCount"
    foreach ($case in $cases) {
        [void](Invoke-StartupSample -Executable $powerShellExecutable -ArgumentList $case.Arguments)
    }
}

for ($sampleIndex = 0; $sampleIndex -lt $SampleCount; $sampleIndex++) {
    Write-Verbose "Sample $($sampleIndex + 1)/$SampleCount"
    foreach ($case in $cases) {
        $elapsed = Invoke-StartupSample -Executable $powerShellExecutable -ArgumentList $case.Arguments
        $measurements[$case.Name].Add($elapsed)
    }
}

$noProfile = Get-StartupStatistics -Samples $measurements.NoProfile
$withProfile = Get-StartupStatistics -Samples $measurements.WithProfile

@(
    [pscustomobject]@{
        Case     = 'NoProfile'
        MedianMs = [Math]::Round($noProfile.MedianMs, 2)
        MeanMs   = [Math]::Round($noProfile.MeanMs, 2)
        P95Ms    = [Math]::Round($noProfile.P95Ms, 2)
        MinMs    = [Math]::Round($noProfile.MinMs, 2)
        MaxMs    = [Math]::Round($noProfile.MaxMs, 2)
    }
    [pscustomobject]@{
        Case     = 'WithProfile'
        MedianMs = [Math]::Round($withProfile.MedianMs, 2)
        MeanMs   = [Math]::Round($withProfile.MeanMs, 2)
        P95Ms    = [Math]::Round($withProfile.P95Ms, 2)
        MinMs    = [Math]::Round($withProfile.MinMs, 2)
        MaxMs    = [Math]::Round($withProfile.MaxMs, 2)
    }
    [pscustomobject]@{
        Case     = 'ProfileIncrement'
        MedianMs = [Math]::Round($withProfile.MedianMs - $noProfile.MedianMs, 2)
        MeanMs   = [Math]::Round($withProfile.MeanMs - $noProfile.MeanMs, 2)
        P95Ms    = [Math]::Round($withProfile.P95Ms - $noProfile.P95Ms, 2)
        MinMs    = [Math]::Round($withProfile.MinMs - $noProfile.MinMs, 2)
        MaxMs    = [Math]::Round($withProfile.MaxMs - $noProfile.MaxMs, 2)
    }
)
