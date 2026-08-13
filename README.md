# powershell-profile

PowerShell 7 profile with native TUI pickers (`sshc`, `proj`, `condac`, `nvmc`) and `setup.ps1` for the tools it needs.

This is a **personal** profile, published as-is for fun. It is not a product, not supported, and not guaranteed to work on any other machine. Steal ideas if you like; expect to edit paths and skip bits that do not apply to you.

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

## Machine-specific

These assume this machine's layout. Change them before using the profile elsewhere.

| Setting | Where | Default / assumption | Used by |
| --- | --- | --- | --- |
| `WORK_ROOT` | `profile.d/00-env.ps1` | `D:/work` | `work` (cd), `proj` (scan git repos under this tree, depth 3) |
| Conda hook | `profile.ps1` (AllHosts) | `%USERPROFILE%\miniconda3\Scripts\conda.exe` | `condac`; skip the block if conda lives somewhere else. `conda init powershell` may rewrite this to an absolute path. |
| WezTerm config | `profile.d/30-aliases.ps1` | `%USERPROFILE%\.config\wezterm` | `wezconf` |
| SSH config | `~/.ssh/config` | OpenSSH user config | `sshc`, `sshls`, `sshconf` |
| WSL config | `%USERPROFILE%\.wslconfig` | Windows WSL2 config | `wslconf` |
| nvm-windows | `NVM_HOME` / `NVM_SYMLINK` | Set by the nvm-windows installer | `nvmc` |

`proj` and `work` do nothing useful until `WORK_ROOT` exists. `condac` needs the AllHosts conda hook loaded (`conda` as a function, not only `conda.exe`). `nvmc` and `wezconf` need the matching optional install (`.\setup.ps1 -Optional`).

## Commands

| Command | What it does |
| --- | --- |
| `work` | `cd` to `WORK_ROOT` |
| `sshc` | Pick an SSH host from `~/.ssh/config` and connect |
| `proj` | Pick a git repo under `WORK_ROOT` and `cd` into it |
| `condac` | Pick a conda env and activate it in this session |
| `nvmc` | Pick an nvm-windows Node version and `nvm use` |
| `help` | List profile functions with a one-line description |
| `reload` | Dot-source the current host profile again |

## Layout

`Microsoft.PowerShell_profile.ps1` dots `profile.d/*.ps1` in filename order (interactive sessions only; `*.lazy.ps1` loads on first use). `profile.ps1` is the AllHosts profile and is managed by conda — do not fold it into the CurrentUser fragments.
