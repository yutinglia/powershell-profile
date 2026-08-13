# Profile feature backlog

Agent handoff for this PowerShell 7 profile. Not a generic plugin list — ideas that attach to the existing `profile.d` loader, native `sshc` TUI, `D:/work`, and the PVE / AWS / Mac homelab line.

| Field | Value |
| --- | --- |
| Status | proposed |
| Date | 2026-08-13 |
| Source | brainstorm chat; canvas `profile-feature-ideas.canvas.tsx` |
| Effort | **S** small fix · **M** one fragment · **L** architecture |

**How to implement one item**

1. Pick a single `id` below.
2. Follow **Implement** (English prompt, copy-paste into a new agent).
3. Match existing style: Dracula tokens (`#282a36` / `#bd93f9` / `#50fa7b`), Nerd Font icons, `profile.d/NN-*.ps1` numbered fragments, comment-based help if you add functions.
4. Check the box when done. Shared TUI picker is `Invoke-ProfilePicker` in `profile.d/00-tui.ps1`.

---

## Current profile (read this first)

Thin loader: `Microsoft.PowerShell_profile.ps1` dots `profile.d/*.ps1` in filename order. Failures print and do not abort the rest.

| Fragment | Role |
| --- | --- |
| `00-env.ps1` | `VIRTUAL_ENV_DISABLE_PROMPT`, `SSH_AUTH_SOCK`, `WORK_ROOT` |
| `00-tui.ps1` | `Invoke-ProfilePicker` native TUI (mouse, hover, details, numbered fallback) |
| `01-secrets.ps1` | OpenRouter / Anthropic keys (gitignored; example is tracked) |
| `10-prompt.ps1` | Terminal-Icons, posh-git, Oh My Posh → `themes/my-theme.omp.json` |
| `20-readline.ps1` | MenuComplete, history prediction, up/down history search |
| `30-aliases.ps1` | `open`, `work`, `conf`, `..` / `...`, `nx`, `pm`, `wezconf`, `ompconf`, `reload`, `touch`, `wslconf` |
| `40-ssh.ps1` | `sshconf`, `sshls`, `sshc` (uses `Invoke-ProfilePicker`) |
| `45-proj.ps1` | `proj` TUI — git repos under `WORK_ROOT` |
| `46-conda.ps1` | `condac` TUI — conda env activate / deactivate |
| `47-nvm.ps1` | `nvmc` TUI — nvm-windows version switch |
| `50-tools.ps1` | `cleanport` (restart WinNAT), `claude_remote` |
| `60-gh-copilot.ps1` | `ghcs`, `ghce` |
| `70-completions.ps1` | Chocolatey only |
| `90-help.ps1` | `help` lists function names + files; `pshelp` → `Get-Help` |

Also: `setup.ps1` + `winget/packages.json` (pwsh, Oh My Posh, Git, gh, VS Code, Terminal-Icons, posh-git, Meslo). AllHosts `profile.ps1` is conda-managed — do not fold it into CurrentUser fragments.

Theme is two-line Dracula; keep the full prompt bar in history; clock is on the top-right of the path line. `sshc` already parses Host / HostName / User / Port / IdentityFile / ProxyJump / LocalForward and a leading `#` note.

**Out of scope on purpose:** weather, fortune, huge git alias packs, wrapping fzf again, extra Oh My Posh language segments.

---

## Do first

TUI engine lives in `profile.d/00-tui.ps1` (`Invoke-ProfilePicker`); `sshc` and `proj` both use it.

### 1. `proj` — project picker · M · tui · done

`work` cds to `WORK_ROOT`; `proj` scans git repos under that tree.

### 2. `killport` — free a port · S · qol

`cleanport` only restarts WinNAT. nx/node occupying 3000/4200 needs PID lookup and stop. Pair with `ports`.

- Implement: Add `killport <port>` that finds the listening process and stops it, plus tab completion for listening ports.

### 3. `sshc-recent` — pin recent hosts · S · ssh

Hosts sort alphabetically; frequent ones disappear. Persist last-used names and pin them at the top of the TUI.

- Implement: Remember recently connected sshc hosts and pin them at the top of the TUI list.

---

## Known gaps (fix while touching those files)

| Gap | Where | Notes |
| --- | --- | --- |
| `touch` | `30-aliases.ps1` | Bare `New-Item` — no path, prompts interactively |
| `help` | `90-help.ps1` | Names + files only; no one-line description |
| `reload` | `30-aliases.ps1` | `. $profile` stacks `Register-ArgumentCompleter` |
| `cleanport` | `50-tools.ps1` | WinNAT only; does not kill a node listener |

---

## Backlog

Checkboxes are the source of truth. **Implement** lines are the agent prompt.

### TUI family

- [x] **`tui-kit`** · `profile.d/00-tui.ps1` · L — Extract a reusable TUI picker from `profile.d/40-ssh.ps1` (Dracula, hover, mouse, dirty redraw) into a shared fragment, then keep sshc using it. *Wait until a second picker exists.*
- [x] **`proj`** · `proj` · M — Add a `proj` TUI that lists git repos under `D:/work`, reusing the sshc picker style, and cds into the selected repo.
- [ ] **`histc`** · `histc` · M — Add a `histc` TUI over PSReadLine/PowerShell history with filter, preview, and insert-or-run.
- [ ] **`awsc`** · `awsc` · S — Add an `awsc` TUI that lists AWS profiles and sets `AWS_PROFILE` for the current session. (Prompt already has an AWS segment.)
- [x] **`condac`** · `condac` · M — Add a `condac` TUI that lists conda envs (`conda env list --json`) and activates the selected one via the AllHosts conda hook. Pin `(deactivate)` at the top when an env is active. *Replaces `envc`; no local venv.*
- [x] **`nvmc`** · `nvmc` · M — Add an `nvmc` TUI that lists nvm-windows versions from `NVM_HOME` and runs `nvm use`. Do not call `nvm.exe` to list (it pops a Terminal Only dialog without a console). Pin `.nvmrc` matches at the top.

### sshc / SSH

- [ ] **`sshc-recent`** · `sshc` · S — Remember recently connected sshc hosts and pin them at the top of the TUI list.
- [ ] **`sshc-copy`** · `Ctrl+Y` · S — Add sshc TUI chords to copy the ssh command or `user@host` to the clipboard without connecting. (`Ctrl+Y` → `ssh host`, `Ctrl+P` → `user@addr`.)
- [ ] **`sshc-include`** · `sshc` · M — Make sshc follow `Include` directives in `~/.ssh/config` when building the host list.
- [ ] **`sshc-groups`** · `sshc` · M — Group sshc hosts by the comment notes already parsed from SSH config.
- [ ] **`sshc-fuzzy`** · `sshc` · S — Change sshc TUI filtering from a single substring to tokenized fuzzy matching. (`pve sh` should match `pve-shell`.)
- [ ] **`fwd`** · `fwd` · M — Add a `fwd` TUI for SSH LocalForward hosts: start/stop tunnels without a full interactive SSH session.

### Daily QoL

- [ ] **`killport`** · `killport 3000` · S — Add `killport <port>` that finds the listening process and stops it, plus tab completion for listening ports.
- [ ] **`ports`** · `ports` · S — Add a `ports` command that lists listening TCP ports with PID and process name.
- [x] **`touch-fix`** · `touch file` · S — Fix the `touch` function so it accepts paths, creates files, and updates timestamps if they exist.
- [x] **`help-desc`** · `help` · S — Extend the profile `help` command to show a one-line description per function from comment-based help.
- [ ] **`reload-safe`** · `reload` · S — Make `reload` safe to run repeatedly without stacking argument completers or duplicate functions.
- [x] **`psreadline`** · `20-readline.ps1` · S — Upgrade `profile.d/20-readline.ps1`: ListView predictions, no bell, Ctrl+Backspace, Dracula colors.
- [ ] **`which`** · `which sshc` · S — Add a `which` helper that prints whether a name is an alias, function, or executable, and where it is defined.
- [ ] **`profup`** · `profup` · S — Add `profup` to `git pull` the PowerShell profile repo and reload the current host profile.
- [ ] **`lazy`** · `Microsoft.PowerShell_profile.ps1` · M — Speed up profile startup: skip non-interactive sessions and lazy-load Chocolatey, gh-copilot, and similar fragments.

### Navigation

- [ ] **`zoxide`** · `z` · S — Add zoxide (`z`) to the profile and optional `setup.ps1` install via winget.
- [ ] **`mkcd`** · `mkcd path` · S — Add `mkcd` that creates a directory (and parents) then sets location there.
- [ ] **`up`** · `up 3` · S — Add an `up [n]` function that changes location n directories toward the root.
- [ ] **`wslpath`** · `wslpath` · S — Add `wslpath` helpers to convert between Windows and WSL paths, plus open the counterpart in explorer or the WSL shell.

### Git

Prompt already shows git status; profile has almost no git verbs. Keep the alias set small.

- [ ] **`gitc`** · `gitc` · M — Add a `gitc` TUI to pick and checkout local/remote branches, showing dirty status in the details pane.
- [ ] **`repo`** · `repo` · S — Add a `repo` function that cds to the current git worktree root.
- [ ] **`gst`** · `gst` / `gco` / `gpr` · S — Add a small git alias set: `gst`, `gco`, `glog`, and `gpr` wrapping `gh pr view --web`.

### Completions / secrets / homelab

- [ ] **`complete`** · `70-completions.ps1` · S — Register tab completions for `gh`, `winget`, and ssh hosts in `profile.d/70-completions.ps1`.
- [ ] **`secrets`** · `01-secrets.ps1` · M — Move OpenRouter/Anthropic secrets from plaintext `01-secrets.ps1` into Windows Credential Manager or SecretManagement.
- [ ] **`lab`** · `lab` · M — Add a `lab` command that probes SSH hosts tagged as homelab (pve, opnsense, mac) and prints reachability.

---

## Style constraints for agents

- New helpers go in the matching `profile.d` fragment (or a new numbered file). Do not grow `Microsoft.PowerShell_profile.ps1`.
- Do not commit `profile.d/01-secrets.ps1`.
- `sshc` TUI: VT mouse (`1003`), synchronized updates (`CSI ?2026`), C0 bytes for Ctrl chords and Backspace (`0x08` / `0x7F`). Redirected stdin/stdout still uses the numbered fallback menu.
- Prefer native PowerShell over new dependencies. If a tool is required, add it to `setup.ps1` (required vs `-Optional`) and `winget/packages.json`.
- User-facing chat is Traditional Chinese; commit messages follow Conventional Commits in English.
