Set-Alias -Name open -Value ii

function work {
    <#
    .SYNOPSIS
        Change location to WORK_ROOT.
    #>
    Set-Location $env:WORK_ROOT
}

function conf {
    <#
    .SYNOPSIS
        Open the profile folder in VS Code.
    #>
    code (Split-Path -Parent $profile)
}

function config {
    <#
    .SYNOPSIS
        Open the profile folder in VS Code (alias of conf).
    #>
    conf
}

function .. {
    <#
    .SYNOPSIS
        Change location to the parent directory.
    #>
    Set-Location ..
}

function ... {
    <#
    .SYNOPSIS
        Change location two directories up.
    #>
    Set-Location ..\..
}

function nx {
    <#
    .SYNOPSIS
        Run nx via npx.
    #>
    npx nx @args
}

function pm {
    <#
    .SYNOPSIS
        Run pnpm.
    #>
    pnpm @args
}

function wezconf {
    <#
    .SYNOPSIS
        Open the WezTerm config folder in VS Code.
    #>
    code $env:USERPROFILE\.config\wezterm
}

function ompconf {
    <#
    .SYNOPSIS
        Open the Oh My Posh theme in VS Code.
    #>
    code (Join-Path (Split-Path -Parent $profile) 'themes\my-theme.omp.json')
}

function reload {
    <#
    .SYNOPSIS
        Dot-source the current host profile again.
    #>
    . $profile
}

function touch {
    <#
    .SYNOPSIS
        Create files or update their last-write timestamps.
    .PARAMETER Path
        One or more paths. Missing files are created empty; existing files get LastWriteTime = now.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Path
    )

    if (-not $Path -or $Path.Count -eq 0) {
        Write-Error 'touch: missing file operand'
        return
    }

    foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p) {
            (Get-Item -LiteralPath $p).LastWriteTime = Get-Date
        }
        else {
            New-Item -ItemType File -Path $p | Out-Null
        }
    }
}

function wslconf {
    <#
    .SYNOPSIS
        Open .wslconfig in VS Code.
    #>
    code $env:USERPROFILE\.wslconfig
}
