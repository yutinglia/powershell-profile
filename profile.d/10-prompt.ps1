function global:prompt {
    $lastCommandSucceeded = $?
    $lastExitCode = $global:LASTEXITCODE
    $location = $ExecutionContext.SessionState.Path.CurrentLocation.Path
    $promptColor = if ($lastCommandSucceeded) { '255;121;198' } else { '255;85;85' }

    $global:LASTEXITCODE = $lastExitCode
    "`e[38;2;189;147;249m$location`e[0m`n`e[38;2;${promptColor}m❯`e[0m "
}

try {
    Set-PSReadLineOption -ExtraPromptLineCount 1
}
catch {
}

$profileOmpTheme = [System.IO.Path]::Combine(
    [System.IO.Directory]::GetParent($PSScriptRoot).FullName,
    'themes\my-theme.omp.json'
)
$profileOmpCommand = if (-not $env:CURSOR_AGENT) {
    Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue
}

if ($env:CURSOR_AGENT) {
    # Cursor agent shells intentionally keep the lightweight fallback prompt.
}
elseif (-not $profileOmpCommand) {
    Write-Host 'Oh My Posh is not installed. Run .\setup.ps1' -ForegroundColor Yellow
}
elseif (-not [System.IO.File]::Exists($profileOmpTheme)) {
    Write-Host "Oh My Posh theme not found: $profileOmpTheme" -ForegroundColor Yellow
}
else {
    $profileOmpState = Get-Variable -Name '__ProfileOhMyPoshState' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $profileOmpState -or $profileOmpState.Owner -ne 'PowerShell.Profile.OhMyPosh/v1') {
        $profileOmpState = [pscustomobject]@{
            Owner              = 'PowerShell.Profile.OhMyPosh/v1'
            Status             = 'NotStarted'
            IdleSubscriptionId = $null
            IdleJobId          = $null
            Executable         = $null
            Theme              = $null
            Error              = $null
        }
        Set-Variable -Name '__ProfileOhMyPoshState' -Scope Global -Value $profileOmpState
    }

    if ($profileOmpState.IdleSubscriptionId) {
        $profileOmpIdleSubscriber = Get-EventSubscriber -SubscriptionId $profileOmpState.IdleSubscriptionId -ErrorAction SilentlyContinue
        if (
            $profileOmpIdleSubscriber -and
            $profileOmpIdleSubscriber.SourceIdentifier -eq 'PowerShell.OnIdle' -and
            $profileOmpIdleSubscriber.Action -and
            $profileOmpIdleSubscriber.Action.Id -eq $profileOmpState.IdleJobId
        ) {
            Unregister-Event -SubscriptionId $profileOmpIdleSubscriber.SubscriptionId -ErrorAction SilentlyContinue
        }
    }

    if ($profileOmpState.IdleJobId) {
        $profileOmpIdleJob = Get-Job -Id $profileOmpState.IdleJobId -ErrorAction SilentlyContinue
        if ($profileOmpIdleJob -and $profileOmpIdleJob.Name -eq 'PowerShell.OnIdle') {
            Remove-Job -Id $profileOmpIdleJob.Id -Force -ErrorAction SilentlyContinue
        }
    }

    $profileOmpState.Status = 'NotStarted'
    $profileOmpState.IdleSubscriptionId = $null
    $profileOmpState.IdleJobId = $null
    $profileOmpState.Executable = $profileOmpCommand.Source
    $profileOmpState.Theme = $profileOmpTheme
    $profileOmpState.Error = $null

    $profileOmpIdleJob = $null
    try {
        $profileOmpIdleJob = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
            $state = Get-Variable -Name '__ProfileOhMyPoshState' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
            if ($state -and $state.Owner -eq 'PowerShell.Profile.OhMyPosh/v1') {
                $state.Status = 'Initializing'
                try {
                    $initScript = & $state.Executable init pwsh --config $state.Theme | Out-String
                    if ($LASTEXITCODE -ne 0 -or -not $initScript.Trim()) {
                        throw "oh-my-posh init exited with code $LASTEXITCODE."
                    }

                    $initScript | Invoke-Expression
                    $generatedPrompt = Get-Command prompt -CommandType Function -ErrorAction Stop
                    $null = $ExecutionContext.SessionState.InvokeProvider.Item.Set(
                        'Function:\global:prompt',
                        $generatedPrompt.ScriptBlock
                    )
                    $state.Status = 'Initialized'
                    try {
                        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
                    }
                    catch {
                    }
                }
                catch {
                    $state.Status = 'Failed'
                    $state.Error = $_.Exception.Message
                    Write-Host "Oh My Posh initialization failed: $($state.Error)" -ForegroundColor Yellow
                }
            }

            if ($eventSubscriber) {
                Unregister-Event -SubscriptionId $eventSubscriber.SubscriptionId -ErrorAction SilentlyContinue
            }
        }

        $profileOmpIdleSubscriber = @(
            Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle |
                Where-Object {
                    $_.Action -and $_.Action.Id -eq $profileOmpIdleJob.Id
                }
        )[0]
        if (-not $profileOmpIdleSubscriber) {
            throw 'Unable to identify the Oh My Posh OnIdle subscription.'
        }

        $profileOmpState.IdleSubscriptionId = $profileOmpIdleSubscriber.SubscriptionId
        $profileOmpState.IdleJobId = $profileOmpIdleJob.Id
    }
    catch {
        if ($profileOmpIdleJob) {
            Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle |
                Where-Object {
                    $_.Action -and $_.Action.Id -eq $profileOmpIdleJob.Id
                } |
                ForEach-Object {
                    Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction SilentlyContinue
                }
            Remove-Job -Id $profileOmpIdleJob.Id -Force -ErrorAction SilentlyContinue
        }

        $profileOmpState.Status = 'Initializing'
        try {
            $profileOmpInitScript = & $profileOmpState.Executable init pwsh --config $profileOmpState.Theme | Out-String
            if ($LASTEXITCODE -ne 0 -or -not $profileOmpInitScript.Trim()) {
                throw "oh-my-posh init exited with code $LASTEXITCODE."
            }
            $profileOmpInitScript | Invoke-Expression
            $profileOmpState.Status = 'Initialized'
        }
        catch {
            $profileOmpState.Status = 'Failed'
            $profileOmpState.Error = $_.Exception.Message
            Write-Host "Oh My Posh initialization failed: $($profileOmpState.Error)" -ForegroundColor Yellow
        }
    }

    Remove-Variable -Name profileOmpState, profileOmpIdleSubscriber, profileOmpIdleJob, profileOmpInitScript -ErrorAction SilentlyContinue
}

Remove-Variable -Name profileOmpTheme, profileOmpCommand -ErrorAction SilentlyContinue
