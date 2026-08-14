$script:ProfileFragmentDir = $PSScriptRoot
$script:ProfileLazyLoaded = @{}
$script:ProfileLazyFunctions = @{}
$script:ProfileLazyNatives = @{}
$script:ProfileLazyCompleting = $false

function Import-ProfileLazy {
    <#
    .SYNOPSIS
        Dot-source a deferred profile fragment once.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($script:ProfileLazyLoaded[$Name]) { return }

    $path = [System.IO.Path]::Combine($script:ProfileFragmentDir, $Name)
    if (-not [System.IO.File]::Exists($path)) {
        Write-Host "Failed to load profile fragment '$Name': file not found" -ForegroundColor Red
        return
    }

    foreach ($entry in @($script:ProfileLazyFunctions.GetEnumerator())) {
        if ($entry.Value -eq $Name) {
            try {
                $ExecutionContext.SessionState.InvokeProvider.Item.Remove(
                    [string[]]@("Function:\$($entry.Key)"),
                    $false,
                    $true,
                    $false
                )
            }
            catch {
            }
        }
    }

    try {
        . $path
        foreach ($entry in @($script:ProfileLazyFunctions.GetEnumerator())) {
            if ($entry.Value -ne $Name) { continue }
            $local = Get-Command -Name $entry.Key -CommandType Function -ErrorAction SilentlyContinue
            if ($local -and $local.ScriptBlock) {
                $null = $ExecutionContext.SessionState.InvokeProvider.Item.Set(
                    "Function:\global:$($entry.Key)",
                    $local.ScriptBlock
                )
            }
        }
        $script:ProfileLazyLoaded[$Name] = $true
    }
    catch {
        Write-Host "Failed to load profile fragment '$Name': $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Register-ProfileLazyFunction {
    <#
    .SYNOPSIS
        Register a command stub that loads a lazy fragment on first call.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Command,

        [Parameter(Mandatory)]
        [string]$File
    )

    foreach ($name in $Command) {
        $script:ProfileLazyFunctions[$name] = $File
        $stub = [scriptblock]::Create(@"
            Import-ProfileLazy -Name '$File'
            & (Get-Command -Name '$name' -ErrorAction Stop) @args
"@)
        $null = $ExecutionContext.SessionState.InvokeProvider.Item.Set(
            "Function:\global:$name",
            $stub
        )
    }
}

function Invoke-ProfileLazyNativeCompleter {
    <#
    .SYNOPSIS
        Internal helper for lazy native tab completion.
    #>
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($script:ProfileLazyCompleting) { return }
    $script:ProfileLazyCompleting = $true
    try {
        $commandName = $null
        if ($commandAst) {
            $commandName = $commandAst.GetCommandName()
        }
        if (-not $commandName) { return }
        $commandName = [System.IO.Path]::GetFileName($commandName)
        if ($commandName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
            $commandName = $commandName.Substring(0, $commandName.Length - 4)
        }

        $file = $script:ProfileLazyNatives[$commandName]
        if ($file) {
            Import-ProfileLazy -Name $file
        }

        $full = $null
        try {
            $full = $commandAst.Extent.StartScriptPosition.GetFullScript()
        }
        catch {
        }
        if (-not $full) { return }

        $cursor = $cursorPosition
        if ($null -eq $cursor) {
            $cursor = $full.Length
        }

        $completion = [System.Management.Automation.CommandCompletion]::CompleteInput($full, $cursor, $null)
        $completion.CompletionMatches
    }
    finally {
        $script:ProfileLazyCompleting = $false
    }
}

function Register-ProfileLazyNativeCompleter {
    <#
    .SYNOPSIS
        Record a native command whose first Tab loads a lazy fragment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Command,

        [Parameter(Mandatory)]
        [string]$File
    )

    foreach ($name in $Command) {
        $script:ProfileLazyNatives[$name] = $File
    }
}

Register-ProfileLazyFunction -Command ghcs, ghce -File '60-gh-copilot.lazy.ps1'
Register-ProfileLazyFunction -Command Update-SessionEnvironment, refreshenv -File '70-completions.lazy.ps1'
Register-ProfileLazyNativeCompleter -Command choco -File '70-completions.lazy.ps1'
Register-ProfileLazyNativeCompleter -Command git -File '15-poshgit.lazy.ps1'

# One native completer for all lazy commands. pwsh has no Unregister-ArgumentCompleter;
# a per-command Register plus try/catch around the missing cmdlet threw on every startup.
if ($script:ProfileLazyNatives.Count -gt 0) {
    Register-ArgumentCompleter -Native -CommandName ([string[]]$script:ProfileLazyNatives.Keys) -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        Invoke-ProfileLazyNativeCompleter $wordToComplete $commandAst $cursorPosition
    }
}
