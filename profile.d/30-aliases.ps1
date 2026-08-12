Set-Alias -Name open -Value ii

function work {
    Set-Location D:/work
}

function conf {
    code (Split-Path -Parent $profile)
}

function config {
    conf
}

function .. {
    Set-Location ..
}

function ... {
    Set-Location ..\..
}

function nx {
    npx nx @args
}

function pm {
    pnpm @args
}

function wezconf {
    code C:\Users\yutinglia\.config\wezterm
}

function reload {
    . $profile
}

function touch {
    New-Item
}

function wslconf {
    code $env:USERPROFILE\.wslconfig
}
