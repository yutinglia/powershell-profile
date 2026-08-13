# powershell-profile

PowerShell 7 profile with native TUI pickers (`sshc`, `proj`, `condac`, `nvmc`) and `setup.ps1` for the tools it needs.

## Requirements

- [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)
- [winget](https://learn.microsoft.com/windows/package-manager/winget/) (App Installer from the Microsoft Store)

## Install

Clone into the CurrentUser CurrentHost profile directory (usually `$HOME\Documents\PowerShell`):

```powershell
git clone https://github.com/yutinglia/powershell-profile.git "$HOME\Documents\PowerShell"
cd "$HOME\Documents\PowerShell"
.\setup.ps1
```

`setup.ps1` installs PowerShell 7, Oh My Posh, Git, GitHub CLI, VS Code, Terminal-Icons, and a Nerd Font if none is present. Add `-Optional` for WezTerm, Miniconda, and nvm-windows:

```powershell
.\setup.ps1 -Optional
```

Open a new terminal so PATH and the prompt pick up the new tools.

If this folder is not already your profile directory, copy or symlink it there, or point `$PROFILE` at `Microsoft.PowerShell_profile.ps1`.

## Secrets

`setup.ps1` copies `profile.d/01-secrets.example.ps1` to `profile.d/01-secrets.ps1` when the latter is missing. Fill in your keys locally. That file is gitignored — do not commit real keys.

## Commands

| Command | What it does |
| --- | --- |
| `sshc` | Pick an SSH host from `~/.ssh/config` and connect |
| `proj` | Pick a git repo under `WORK_ROOT` and `cd` into it |
| `condac` | Pick a conda env and activate it in this session |
| `nvmc` | Pick an nvm-windows Node version and `nvm use` |
| `help` | List profile functions with a one-line description |
| `reload` | Dot-source the current host profile again |

## Layout

`Microsoft.PowerShell_profile.ps1` dots `profile.d/*.ps1` in filename order (interactive sessions only; `*.lazy.ps1` loads on first use). `profile.ps1` is the AllHosts profile and is managed by conda — do not fold it into the CurrentUser fragments.
