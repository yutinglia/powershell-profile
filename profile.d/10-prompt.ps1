Import-Module -Name Terminal-Icons
Import-Module posh-git

oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\my-theme.omp.json" | Invoke-Expression
