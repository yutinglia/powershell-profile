Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Ctrl+Backspace -Function BackwardKillWord

Set-PSReadLineOption -BellStyle None -Colors @{
    Command                = "`e[38;2;80;250;123m"
    Keyword                = "`e[38;2;255;121;198m"
    Operator               = "`e[38;2;255;121;198m"
    String                 = "`e[38;2;241;250;140m"
    Parameter              = "`e[38;2;255;184;108m"
    Type                   = "`e[38;2;139;233;253m"
    Number                 = "`e[38;2;189;147;249m"
    Variable               = "`e[38;2;189;147;249m"
    Comment                = "`e[38;2;98;114;164m"
    Default                = "`e[38;2;248;248;242m"
    Error                  = "`e[38;2;255;85;85m"
    Selection              = "`e[48;2;68;71;90m"
    InlinePrediction       = "`e[38;2;98;114;164m"
    ListPrediction         = "`e[38;2;189;147;249m"
    ListPredictionSelected = "`e[38;2;248;248;242m`e[48;2;68;71;90m"
}

try {
    Set-PSReadLineOption -PredictionSource Plugin -PredictionViewStyle ListView -ErrorAction Stop
}
catch {
}

function Invoke-ProfilePredictorInitializationCore {
    function Get-ProfilePredictorAssembly {
        $csPath = Join-Path $PSScriptRoot 'ProfilePredictors.cs'
        if (-not (Test-Path -LiteralPath $csPath)) { return }
        if ('ProfileCommandPredictor' -as [type]) { return }

        $cacheDir = Join-Path $env:LOCALAPPDATA 'pwsh-profile'
        $dll = Join-Path $cacheDir 'ProfilePredictors.dll'
        $keyPath = Join-Path $cacheDir 'ProfilePredictors.key'
        $key = '{0}|{1}|{2}' -f
            (Get-Item -LiteralPath $csPath).LastWriteTimeUtc.Ticks,
            [psobject].Assembly.GetName().Version,
            $PSVersionTable.PSVersion

        if ((Test-Path -LiteralPath $dll) -and (Test-Path -LiteralPath $keyPath) -and
            ((Get-Content -LiteralPath $keyPath -Raw).Trim() -eq $key)) {
            try {
                Add-Type -Path $dll
                return
            }
            catch {
            }
        }

        $compiled = $false
        $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
        $csc = $null
        $refDir = $null
        if ($dotnet) {
            foreach ($line in @(& $dotnet.Source --list-sdks 2>$null)) {
                if ($line -match '^(?<ver>\d+\.\d+\.\d+)\s+\[(?<root>.+)\]$') {
                    $candidate = Join-Path $Matches.root $Matches.ver 'Roslyn\bincore\csc.dll'
                    if (Test-Path -LiteralPath $candidate) { $csc = $candidate }
                }
            }
            $major = [Environment]::Version.Major
            $packRoot = Join-Path ${env:ProgramFiles} 'dotnet\packs\Microsoft.NETCore.App.Ref'
            if (Test-Path -LiteralPath $packRoot) {
                $pack = Get-ChildItem -LiteralPath $packRoot -Directory |
                    Where-Object { $_.Name.StartsWith("$major.") } |
                    Sort-Object Name |
                    Select-Object -Last 1
                if ($pack) {
                    $candidate = Join-Path $pack.FullName "ref\net$major.0"
                    if (Test-Path -LiteralPath $candidate) { $refDir = $candidate }
                }
            }
        }

        if ($dotnet -and $csc -and $refDir) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            $sma = [psobject].Assembly.Location
            $refs = @(
                (Join-Path $refDir 'System.Runtime.dll')
                (Join-Path $refDir 'System.Collections.dll')
                (Join-Path $refDir 'System.Threading.dll')
                (Join-Path $refDir 'netstandard.dll')
                $sma
            )
            $rargs = foreach ($r in $refs) { '/r:"{0}"' -f $r }
            $prevOut = $env:DOTNET_CLI_TELEMETRY_OPTOUT
            $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
            try {
                & $dotnet.Source exec $csc /noconfig /nostdlib /nologo /t:library ("/out:{0}" -f $dll) @rargs $csPath 2>$null
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dll) -and ((Get-Item -LiteralPath $dll).Length -gt 0)) {
                    Set-Content -LiteralPath $keyPath -Value $key -NoNewline
                    Add-Type -Path $dll
                    $compiled = $true
                }
            }
            finally {
                $env:DOTNET_CLI_TELEMETRY_OPTOUT = $prevOut
            }
        }

        if (-not $compiled) {
            Add-Type -TypeDefinition (Get-Content -LiteralPath $csPath -Raw)
        }
    }

    Get-ProfilePredictorAssembly

    $profilePredictNames = [System.Collections.Generic.List[string]]::new()
    $profilePredictTips = [System.Collections.Generic.List[string]]::new()
    $profilePredictFiles = @()
    if ($profile -and (Test-Path -LiteralPath $profile)) {
        $profilePredictFiles += Get-Item -LiteralPath $profile
    }
    if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot)) {
        $profilePredictFiles += Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File
    }

    $profilePredictCacheDir = Join-Path $env:LOCALAPPDATA 'pwsh-profile'
    $profilePredictNameCache = Join-Path $profilePredictCacheDir 'predict-names.json'
    $profilePredictStamp = ($profilePredictFiles | Measure-Object -Property LastWriteTimeUtc -Maximum).Maximum.Ticks
    $profilePredictCached = $false
    if ($profilePredictStamp -and (Test-Path -LiteralPath $profilePredictNameCache)) {
        try {
            $profilePredictJson = Get-Content -LiteralPath $profilePredictNameCache -Raw | ConvertFrom-Json
            if ($profilePredictJson.ticks -eq $profilePredictStamp) {
                foreach ($n in @($profilePredictJson.names)) { $profilePredictNames.Add([string]$n) }
                foreach ($t in @($profilePredictJson.tips)) { $profilePredictTips.Add([string]$t) }
                $profilePredictCached = $true
            }
        }
        catch {
        }
    }

    if (-not $profilePredictCached) {
        foreach ($profilePredictFile in $profilePredictFiles) {
            $profilePredictLines = Get-Content -LiteralPath $profilePredictFile.FullName
            for ($i = 0; $i -lt $profilePredictLines.Count; $i++) {
                if ($profilePredictLines[$i] -notmatch '^function\s+([a-zA-Z0-9_.-]+)') {
                    continue
                }

                $profilePredictName = $Matches[1]
                if ($profilePredictName -match '^(Get|Invoke)-') {
                    continue
                }

                $profilePredictTip = ''
                for ($j = $i + 1; $j -lt $profilePredictLines.Count; $j++) {
                    $trim = $profilePredictLines[$j].Trim()
                    if ($trim -eq '') {
                        continue
                    }
                    if ($trim -eq '{') {
                        continue
                    }
                    if ($trim -eq '<#' -or $trim.StartsWith('<#')) {
                        $inSynopsis = $false
                        $start = if ($trim -eq '<#') { $j + 1 } else { $j }
                        for ($k = $start; $k -lt $profilePredictLines.Count; $k++) {
                            $helpLine = $profilePredictLines[$k].Trim()
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
                                    $profilePredictTip = $helpLine
                                    break
                                }
                            }
                        }
                    }
                    break
                }

                $profilePredictNames.Add($profilePredictName)
                $profilePredictTips.Add($profilePredictTip)
            }
        }

        try {
            New-Item -ItemType Directory -Path $profilePredictCacheDir -Force | Out-Null
            [pscustomobject]@{
                ticks = $profilePredictStamp
                names = [string[]]$profilePredictNames
                tips  = [string[]]$profilePredictTips
            } | ConvertTo-Json -Compress | Set-Content -LiteralPath $profilePredictNameCache -Encoding utf8
        }
        catch {
        }
    }

    $profilePredictHistory = [System.Collections.Generic.List[string]]::new()
    try {
        $profilePredictHistoryPath = (Get-PSReadLineOption).HistorySavePath
        if ($profilePredictHistoryPath -and (Test-Path -LiteralPath $profilePredictHistoryPath)) {
            $profilePredictHistory.AddRange([string[]][System.IO.File]::ReadAllLines($profilePredictHistoryPath))
        }
    }
    catch {
    }

    $subsystemKind = [System.Management.Automation.Subsystem.SubsystemKind]::CommandPredictor
    $predictorInfo = [System.Management.Automation.Subsystem.SubsystemManager]::GetSubsystemInfo($subsystemKind)
    $predictorRegistered = [System.Collections.Generic.HashSet[guid]]::new()
    if ($predictorInfo.IsRegistered) {
        foreach ($impl in $predictorInfo.Implementations) {
            [void]$predictorRegistered.Add($impl.Id)
        }
    }
    foreach ($predictorId in @([ProfileCommandPredictor]::PredictorId, [ProfileHistoryPredictor]::PredictorId)) {
        if ($predictorRegistered.Contains($predictorId)) {
            [System.Management.Automation.Subsystem.SubsystemManager]::UnregisterSubsystem($subsystemKind, $predictorId)
        }
    }

    [System.Management.Automation.Subsystem.SubsystemManager]::RegisterSubsystem(
        $subsystemKind,
        [ProfileCommandPredictor]::new([string[]]$profilePredictNames, [string[]]$profilePredictTips)
    )
    [System.Management.Automation.Subsystem.SubsystemManager]::RegisterSubsystem(
        $subsystemKind,
        [ProfileHistoryPredictor]::new([string[]]$profilePredictNames, [string[]]$profilePredictHistory)
    )

    try {
        Set-PSReadLineOption -PredictionSource Plugin -PredictionViewStyle ListView -ErrorAction Stop
    }
    catch {
    }

    Remove-Variable -Name profilePredictNames, profilePredictTips, profilePredictFiles, profilePredictFile, profilePredictLines, profilePredictName, profilePredictTip, profilePredictHistory, profilePredictHistoryPath, profilePredictCacheDir, profilePredictNameCache, profilePredictStamp, profilePredictCached, profilePredictJson, subsystemKind, predictorId, predictorInfo, predictorRegistered, impl -ErrorAction SilentlyContinue
}

function Get-ProfilePredictorInitializationState {
    $state = Get-Variable -Name '__ProfileReadLinePredictorState' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $state -or $state.Owner -ne 'PowerShell.Profile.ReadLinePredictor/v1') {
        $state = [pscustomobject]@{
            Owner                = 'PowerShell.Profile.ReadLinePredictor/v1'
            InitializationStatus = 'NotStarted'
            IdleSubscriptionId   = $null
            IdleJobId            = $null
        }
        Set-Variable -Name '__ProfileReadLinePredictorState' -Scope Global -Value $state
    }

    $state
}

function Invoke-ProfilePredictorInitialization {
    <#
    .SYNOPSIS
        Initialize the profile command and history predictors once per session.
    #>
    [CmdletBinding()]
    param()

    $state = Get-ProfilePredictorInitializationState
    if ($state.InitializationStatus -in 'Initializing', 'Initialized') {
        return
    }

    $state.InitializationStatus = 'Initializing'
    try {
        Invoke-ProfilePredictorInitializationCore
        $state.InitializationStatus = 'Initialized'
    }
    catch {
        $state.InitializationStatus = 'NotStarted'
        throw
    }
}

$profilePredictorState = Get-ProfilePredictorInitializationState
$profilePredictorIdleSubscriber = $null
if ($profilePredictorState.IdleSubscriptionId) {
    $profilePredictorIdleSubscriber = Get-EventSubscriber -SubscriptionId $profilePredictorState.IdleSubscriptionId -ErrorAction SilentlyContinue
    if (
        $profilePredictorIdleSubscriber -and
        $profilePredictorIdleSubscriber.SourceIdentifier -eq 'PowerShell.OnIdle' -and
        $profilePredictorIdleSubscriber.Action -and
        $profilePredictorIdleSubscriber.Action.Id -eq $profilePredictorState.IdleJobId
    ) {
        Unregister-Event -SubscriptionId $profilePredictorIdleSubscriber.SubscriptionId -ErrorAction SilentlyContinue
    }
}

if ($profilePredictorState.IdleJobId) {
    $profilePredictorIdleJob = Get-Job -Id $profilePredictorState.IdleJobId -ErrorAction SilentlyContinue
    if ($profilePredictorIdleJob -and $profilePredictorIdleJob.Name -eq 'PowerShell.OnIdle') {
        Remove-Job -Id $profilePredictorIdleJob.Id -Force -ErrorAction SilentlyContinue
    }
}

$profilePredictorState.IdleSubscriptionId = $null
$profilePredictorState.IdleJobId = $null

if ($profilePredictorState.InitializationStatus -ne 'Initialized') {
    $profilePredictorIdleJob = $null
    try {
        $profilePredictorIdleJob = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
            try {
                Invoke-ProfilePredictorInitialization
            }
            catch {
            }
            finally {
                if ($eventSubscriber) {
                    Unregister-Event -SubscriptionId $eventSubscriber.SubscriptionId -ErrorAction SilentlyContinue
                }
            }
        }

        $profilePredictorIdleSubscriber = @(
            Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle |
                Where-Object {
                    $_.Action -and $_.Action.Id -eq $profilePredictorIdleJob.Id
                }
        )[0]
        if (-not $profilePredictorIdleSubscriber) {
            throw 'Unable to identify the profile predictor OnIdle subscription.'
        }

        $profilePredictorState.IdleSubscriptionId = $profilePredictorIdleSubscriber.SubscriptionId
        $profilePredictorState.IdleJobId = $profilePredictorIdleJob.Id
    }
    catch {
        if ($profilePredictorIdleJob) {
            Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle |
                Where-Object {
                    $_.Action -and $_.Action.Id -eq $profilePredictorIdleJob.Id
                } |
                ForEach-Object {
                    Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction SilentlyContinue
                }
            Remove-Job -Id $profilePredictorIdleJob.Id -Force -ErrorAction SilentlyContinue
        }

        $profilePredictorState.IdleSubscriptionId = $null
        $profilePredictorState.IdleJobId = $null
        try {
            Invoke-ProfilePredictorInitialization
        }
        catch {
        }
    }
}

Remove-Variable -Name profilePredictorState, profilePredictorIdleSubscriber, profilePredictorIdleJob -ErrorAction SilentlyContinue
