<p align="right"><a href="https://github.com/fontnelle/dudu/tree/main">macOS · Linux</a> · <b>Windows</b></p>

<div align="center">
  <h1>dudu for Windows</h1>
  <p><b>Back up your whole dev setup in one command and put it back on a new machine in another. Packages, runtimes, dotfiles and terminal, on Windows.</b></p>
  <p>English · <a href="README.pt-BR.md">Português</a> · <a href="README.es.md">Español</a></p>
  <a href="https://github.com/fontnelle/dudu/stargazers"><img src="https://img.shields.io/github/stars/fontnelle/dudu?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/fontnelle/dudu/releases"><img src="https://img.shields.io/github/v/release/fontnelle/dudu?filter=win-v*&label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/fontnelle/dudu/actions/workflows/ci.yml?query=branch%3Awindows"><img src="https://img.shields.io/github/actions/workflow/status/fontnelle/dudu/ci.yml?branch=windows&label=tests&style=flat-square" alt="Tests"></a>
  <a href="#quick-start"><img src="https://img.shields.io/badge/platform-Windows-lightgrey?style=flat-square" alt="Platform"></a>
</div>

dudu is written in bash, so on Windows it runs in **Git Bash** (part of Git for Windows, which most dev machines already have). The installer sets it up when it is missing, and `dudu` then works from PowerShell, cmd and Git Bash alike.

## Features

- **Everything you installed**: winget, scoop and Chocolatey packages, Node versions (nvm-windows, fnm, volta), global npm/pnpm/yarn/bun packages, pipx/uv, gems, cargo, go tools, VS Code and Cursor extensions
- **Your terminal, as it was**: Windows Terminal settings, PowerShell profiles, Git Bash (`.bashrc`, `.minttyrc`), Starship, Neovim, WezTerm, Alacritty, Nerd Fonts, git and SSH config
- **Saved where you already are**: a local folder, Google Drive and iCloud for Windows, several at once
- **Moves between systems**: a Mac's backup restores here (Homebrew becomes winget and scoop), and a Windows backup restores on a Mac or Linux
- **Secrets stay home**: tokens in your dotfiles are masked, key files are never copied, and `dudu secrets` moves keys out of your `.bashrc`
- **Encrypted if you want**: AES-256 with a password kept in the Windows Credential Manager
- **Safe to restore**: a backup is treated as untrusted, checked against its checksums, and never overwrites a file without keeping a copy
- **Runs by itself**: a daily backup with `dudu schedule on`, through Task Scheduler
- **Speaks your language**: English, Português (Brasil) and Español, picked from your system
- **Pure bash, no other dependencies**: Git for Windows brings everything dudu uses (bash, curl, openssl, tar)

## Quick Start

**Install from PowerShell**

```powershell
irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
```

It installs Git for Windows with winget if Git Bash is missing, installs dudu, and adds `dudu` to your PATH for PowerShell and cmd. Open a new terminal afterwards.

**Or from Git Bash**

```bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/windows/install.sh | bash
```

Both verify the release against its `SHA256SUMS`. A version: `$env:DUDU_VERSION = "0.1.0"` before `install.ps1`, or `| bash -s -- 0.1.0`.

**Run**

```bash
dudu                 # interactive menu
dudu backup          # save everything to your destinations
dudu restore         # on the new machine: reinstall everything
dudu status          # what changed since the last backup
dudu outdated        # updates for winget, scoop, npm, pip, gems... then update all or pick
dudu secrets         # keys found in your config files, and moving them to ~/.secrets
dudu schedule on     # a backup every day (12:30, or: dudu schedule on 08:00)
dudu config          # destinations, language, encryption, schedule
```

Every command takes `--dry-run` and `--only brew,node,...`. `restore` also takes `--from <machine>` (a backup from another computer), `--file <folder>` (a backup copied by hand) and `--yes`. `--debug` traces every step into `~/.cache/dudu/dudu.log`.

## New machine, step by step

```powershell
irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
dudu config                       # the same destination as the old machine
dudu restore --dry-run            # see what will happen
dudu restore
```

The restore runs in order: winget, scoop and Chocolatey packages first, then the shell and git config, Node versions, global packages and editors. Every step is idempotent: what is already installed is skipped, and a file that differs is kept as `<file>.dudu-bak`. Chocolatey installs need a terminal opened as administrator; winget asks for permission itself when an installer needs it.

## From a Mac to Windows

A backup made on a Mac restores on Windows too, as far as Windows allows. Google Drive is the bridge: both machines reach it through `rclone`, set up by `dudu config gdrive`.

```bash
# On the Mac: connect Google Drive, then back up
dudu config gdrive
dudu backup

# On Windows
dudu config gdrive              # 1: the same Google account, it lists the Mac
dudu restore --dry-run --from <mac name>
dudu restore --from <mac name>
```

- **Homebrew becomes winget packages.** Formulae and casks with a winget package are installed with it (`git` becomes `Git.Git`, `visual-studio-code` becomes `Microsoft.VisualStudioCode`...). With scoop installed, what winget has no package for is tried with scoop under the same name. GNU tools that Git Bash already has (coreutils, grep, sed...) are skipped.
- **Runtimes use their Windows installers.** nvm becomes nvm-windows when it is installed, or fnm otherwise; rustup and bun come from winget.
- **Settings follow the paths of Windows.** VS Code and Cursor settings move from `~/Library/Application Support` to `AppData\Roaming`.
- **Before anything is installed, the plan lists what is left out:** Mac App Store apps, casks with no Windows build, macOS preferences, Terminal.app/iTerm2 profiles and anything else under `~/Library`.

A backup made on Windows restores on a Mac or Linux the same way: editor settings move to their place there, and winget, scoop and Windows Terminal are listed as left out. The names that differ are in [`lib/data/brew-windows.map`](lib/data/brew-windows.map). A missing app is one line away.

## Where backups go

| Destination | Where | Notes |
| --- | --- | --- |
| Local folder | `~/dudu-backups` or any folder | Default |
| Google Drive | `My Drive/dudu-<machine>` | `dudu config gdrive`, in 4 steps (see below). Drive for desktop is used when it is installed (`G:\My Drive`, or its mirrored folder). Another synced folder: `dudu config set gdrive_path <folder>` |
| iCloud Drive | `iCloudDrive\dudu` | With iCloud for Windows |

Apple Notes, a destination on macOS, does not exist on Windows.

**`dudu config gdrive`** saves straight to Google Drive, without Drive for desktop:

1. **rclone**: installs it (with winget, scoop or Chocolatey) if needed.
2. **Folder**: choose **1, connect my Google account**, and dudu creates `dudu-<machine>` in My Drive. It then sees only the files it creates (`drive.file` access), nothing else of your Drive. Or choose **2, paste the link of a folder** you already have (in Drive: right-click › Share › Copy link). A wrong link says why: a file instead of a folder, another site, a short link. A pasted folder needs access to the whole Drive, and each machine gets its `dudu-<machine>` inside it.
3. **Google account**: a browser opens to sign in once. dudu uses an rclone remote of its own (`dudu-gdrive`), so your other remotes are left alone.
4. **Checks**: a test file is written, read back and removed. rclone's config, which holds the Google token, stays in your `AppData`, which only you can read. If encryption is off, dudu offers to turn it on, and it lists the machines already backed up there.

At the end, and after each backup, dudu shows the link of the folder to open it in the browser. If a step fails, nothing is saved and the previous settings stay. A Mac that saves through Drive for desktop: on Windows, choose 2 and paste the link of its `dudu` folder, which dudu did not create and cannot see with `drive.file`.

Pick **one or more** with `dudu config` or `dudu config set destination local,gdrive`. Each backup goes to all of them, and one failing does not stop the others. `restore` and `status` read the newest backup found across them. Folders keep the latest 5 backups per machine (`dudu config set keep 10`).

## What gets backed up

| Collector | Saves | Restores with |
| --- | --- | --- |
| `winget` | the ids of the packages winget knows (`winget export`) | `winget install` each missing one |
| `scoop` | buckets and apps (`scoop export`) | `scoop bucket add`, `scoop install` |
| `choco` | Chocolatey packages | `choco install` (in an administrator terminal) |
| `brew` | a Mac's or Linux's Brewfile, when restoring their backup here | winget and scoop packages (see above) |
| `shell` | `.bashrc`, `.bash_profile`, `.minttyrc`, PowerShell profiles, `starship.toml`, vim, Neovim (`AppData\Local\nvim`) | copies files |
| `git` | `.gitconfig`, global gitignore, `~/.ssh/config`, gh config | copies files |
| `terminal` | Windows Terminal (`settings.json`), WezTerm, Alacritty, the list of Nerd Fonts | copies files |
| `node` | nvm-windows (or nvm, fnm, volta) versions and the default | `nvm install`, or fnm when nvm-windows is not there |
| `npm` `pnpm` `yarn` `bun` | global packages, `.npmrc` | `npm install -g` ... |
| `python` | pyenv versions, pipx and uv tools, `pip --user` | `pipx install`, `uv tool install`, `pip install --user` |
| `ruby` `cargo` `go` | gems, `cargo install` crates, `go install` tools | the same tools (rustup and bun from winget) |
| `vscode` `cursor` | extensions, settings, keybindings, snippets | `code --install-extension` |

Skip collectors with `dudu config set exclude choco,ruby`, or keep only some with `dudu config set include brew,node,shell`.

## Security

**Secrets stay on your machine**

- Values that look like secrets (`TOKEN=`, `_authToken=`, `password:`, `api_key`, `Bearer …`, `https://user:pass@`, `ghp_…`, `sk-…`, `npm_…`, `AKIA…`, JWTs, private key blocks) become `<redacted-by-dudu>` in the backup. References like `$MY_VAR` are kept.
- Key files are never copied: `~/.ssh/id_*`, `~/.gnupg`, `~/.aws/credentials`, `~/.netrc`, `~/.kube/config`, `~/.docker/config.json`, `gh` tokens, `~/.secrets`. dudu lists the ones it found so you can move them yourself.
- A file dudu cannot check for secrets is left out of the backup, never copied as is.
- Each backup ends with the keys it masked: file, line and name, never the value. `dudu secrets` offers to move the `export NAME=…` lines of your shell files to `~/.secrets`, which your `.bashrc` then loads from the same spot.
- On restore, a file whose only difference is the masked secret is left alone, so restoring on the same machine never wipes your tokens.

**Encryption**

`dudu config set encrypt on` asks for a password (12+ characters) and keeps it in the Windows Credential Manager (or, if that fails, in `~/.config/dudu/key`). Each backup then becomes one `backup.enc` (AES-256-CBC, PBKDF2 with 200,000 rounds, via `openssl`) plus a MAC checked before anything is decrypted. Only `manifest.json` (machine name, date, which tools) and a generic `RESTORE.md` stay readable. On a new machine, `dudu restore` asks for the password. **Without it the backup cannot be restored**, so keep it in your password manager.

**What a backup can and cannot do to you**

Anyone with access to the Google Drive or iCloud account can change a backup folder there, so dudu treats it as untrusted on restore:

- package names are checked (no options, URLs or paths) before they reach `winget`, `scoop`, `npm`, `pip`...;
- a Brewfile keeps only `tap`/`brew`/`cask`/`mas`/`vscode` lines, so it cannot run Ruby;
- files go back only to the paths each tool backs up, never to `~/.ssh/authorized_keys`, the Startup folder or `~/.secrets`, and never through a symlink;
- every overwritten file is kept as `.dudu-bak`.

With encryption on, the MAC check comes first: a changed backup is refused before anything runs.

## Reliability

- Every backup carries a `SHA256SUMS`. Saves go to a `.partial` folder, are checked, then renamed, so an interrupted save never becomes the backup restore uses.
- `restore` and `status` check the checksums and fall back to the previous backup when the newest is damaged.
- A tool that fails or times out keeps its copy from the last good backup, and the backup says so instead of "complete".
- `keep` is never less than 1, and pruning never removes the newest complete backup or the one just saved.
- Two machines with the same name back up to separate folders, told apart by a hashed hardware id.
- One dudu runs at a time. Ctrl-C stops the running step and everything it started, and removes temp files.

**Exit codes**

| Code | Meaning |
| --- | --- |
| 0 | Everything worked |
| 1 | Error: nothing was saved or restored |
| 2 | Partly done: a destination failed, a tool could not be read, or a restore step failed |
| 3 | `status` only: this machine changed since the last backup |
| 130 | Interrupted (Ctrl-C) |

## Scheduled backups

`dudu schedule on [HH:MM]` adds a daily backup: a Task Scheduler task named `dudu backup`, which runs while you are signed in, without opening a window. It uses the stored backup password, and a failure shows a Windows notification. `dudu schedule status` shows it, `dudu schedule off` removes it.

## Language

dudu speaks English, Português (Brasil) and Español. It follows your Windows display language (Settings › Time & language) with nothing to set up, and the first run says which one it picked.

```bash
dudu config set language es      # en, pt-BR, es, or auto to follow the system again
DUDU_LANG=en dudu status         # one command in another language
```

Or from the menu: **Settings › Language**. A backup's `RESTORE.md` is written in the language of the machine that made it.

## Tab completion

```bash
echo 'eval "$(dudu completion bash)"' >> ~/.bashrc              # Git Bash
```

## Adding a collector

Each tool is one file in `lib/collectors/<name>.sh`:

```bash
foo_detect()   { has foo; }                                   # is it on this machine?
foo_backup()   { foo list > "$1/list.txt" || return 1; summary "$1" "$(tn "%d thing" "%d things" "$n")"; }
foo_restore()  { act foo install ...; }                        # act runs, or prints in --dry-run
foo_outdated() { foo outdated; }                              # optional: "name current latest" per line
foo_upgrade()  { foo upgrade "$1"; }                          # optional: updates one package
```

Then add the name to `DUDU_COLLECTORS` in `lib/core/common.sh` (the order is the restore order). A backup function returns non-zero when its tool fails, so dudu keeps the last good copy. Pass package lists through `missing_pkgs` and config files through `save_file` and `restore_home <dir> <allowed paths>`: they validate names, mask secrets and keep `.dudu-bak` copies.

## Development

```bash
make check     # shellcheck + bats + translation catalogs
make install   # link this checkout as ~/.local/bin/dudu
```

This branch is the Windows edition. Everything Windows-specific sits behind `is_windows` (`lib/core/platform.sh`), so `main` merges in cleanly, and the code still runs on macOS (bash 3.2) and Linux. Tests fake Windows with `fake_windows` (`tests/helpers.bash`), so `make check` runs anywhere. CI runs them in Git Bash on Windows, and on macOS, bash 3.2, Ubuntu, Fedora and Arch. Releases are tagged `win-vX.Y.Z`, with notes in [`CHANGELOG.windows.md`](CHANGELOG.windows.md).

## License

MIT.
