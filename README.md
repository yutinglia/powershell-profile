# powershell-profile

PowerShell 7 profile with native TUI pickers (`sshc`, `proj`, `condac`, `nvmc`, `gitc`) and `setup.ps1` for the tools it needs.

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
| Conda hook | `profile.ps1` (AllHosts) | `%USERPROFILE%\miniconda3\shell\condabin\Conda.psm1` | `condac`. Imports the module on first `conda`/`condac`; does **not** auto-activate `base`. `conda init powershell` may rewrite this to the slow generated hook. |
| WezTerm config | `profile.d/30-aliases.ps1` | `%USERPROFILE%\.config\wezterm` | `wezconf` |
| SSH config | `~/.ssh/config` | OpenSSH user config | `sshc`, `sshls`, `sshconf` |
| WSL config | `%USERPROFILE%\.wslconfig` | Windows WSL2 config | `wslconf` |
| nvm-windows | `NVM_HOME` / `NVM_SYMLINK` | Set by the nvm-windows installer | `nvmc` |

`proj` and `work` do nothing useful until `WORK_ROOT` exists. `condac` needs the AllHosts conda stub (`conda` as a function, not only `conda.exe`). `nvmc` and `wezconf` need the matching optional install (`.\setup.ps1 -Optional`).

## Commands

| Command | What it does |
| --- | --- |
| `work` | `cd` to `WORK_ROOT` |
| `sshc` | Pick an SSH host from `~/.ssh/config` and connect |
| `proj` | Pick a git repo under `WORK_ROOT` and `cd` into it |
| `condac` | Pick a conda env and activate it in this session |
| `nvmc` | Pick an nvm-windows Node version and `nvm use` |
| `gitc` | Pick a local or remote git branch and check it out |
| `repo` | `cd` to the current git worktree root |
| `ghcs` / `ghce` | GitHub Copilot suggest / explain (loads on first call) |
| `help` | List profile functions with a one-line description |
| `reload` | Dot-source the current host profile again |

## Layout

`Microsoft.PowerShell_profile.ps1` is the CurrentUser CurrentHost loader. Its startup path uses .NET file enumeration, dots `profile.d/*.ps1` in filename order, skips `*.lazy.ps1` and `*.example.ps1`, and **returns immediately** for non-interactive one-shots (`pwsh -Command` / `-File` / `-NonInteractive` without `-NoExit`). Fragment failures print in red and do not abort the rest.

`*.lazy.ps1` files are **not** dotted at startup. `profile.d/00-lazy.ps1` registers stubs; the fragment loads on first use:

| First use | Loads |
| --- | --- |
| `ls` / `dir` / `Get-ChildItem` | Terminal-Icons |
| `git` Tab | posh-git |
| `ghcs` / `ghce` | GitHub Copilot helpers |
| `choco` Tab / `refreshenv` | Chocolatey profile |

`profile.ps1` is AllHosts. It only sets conda env vars and a `conda` stub; `Conda.psm1` imports on first `conda` / `condac`. It does **not** auto-activate `base`. Do not fold AllHosts into CurrentUser fragments. `conda init powershell` may rewrite this file to the slow generated hook — restore the stub if startup jumps back to seconds.

`profile.d/10-prompt.ps1` installs a two-line Dracula fallback immediately, tells PSReadLine about its extra line, then schedules the official `oh-my-posh init` on a profile-owned, one-shot `PowerShell.OnIdle` subscription. That idle callback is the only deferred layer: once the full cached prompt is installed, PSReadLine erases both fallback lines and redraws without an intermediate `PS>` prompt. Running the official init once per shell also gives every session its own `POSH_SESSION_ID`. If Oh My Posh or the theme is missing, the fallback remains active and the profile prints a warning.

PSReadLine key bindings, colors, and basic options are applied synchronously. `profile.d/20-readline.ps1` defers the custom predictor assembly, command index, history read, and subsystem registration to one profile-owned `PowerShell.OnIdle` subscription. Initialization is once per session and idempotent; `reload` replaces only a pending profile subscription and leaves unrelated `PowerShell.OnIdle` subscribers alone.

Oh My Posh now manages its generated init cache in its own application cache directory. `%LOCALAPPDATA%\pwsh-profile` is used only for the predictor DLL/key and command-name cache. A legacy `%LOCALAPPDATA%\pwsh-profile\omp-init.ps1` may remain, but this profile no longer reads or writes it.

## Startup benchmark

Run the benchmark from a warm, otherwise idle system:

```powershell
pwsh -NoProfile -File .\scripts\Measure-ProfileStartup.ps1 -WarmupCount 2 -SampleCount 15
```

The script times the same interactive startup arguments with and without the profile: `pwsh -NoLogo -NoProfile -NoExit -Command exit` and `pwsh -NoLogo -NoExit -Command exit`. It reports median, mean, nearest-rank p95, minimum, maximum, and the profile increment (`WithProfile - NoProfile`). It does not clear Oh My Posh, predictor, filesystem, or runtime caches.
