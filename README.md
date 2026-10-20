<div align="center">
  <h1>dudu</h1>
  <p><b>Back up your whole dev setup in one command and put it back on a new machine in another. Packages, runtimes, dotfiles and terminal, on macOS and Linux.</b></p>
  <p>English · <a href="README.pt-BR.md">Português</a> · <a href="README.es.md">Español</a></p>
  <a href="https://github.com/fontnelle/dudu/stargazers"><img src="https://img.shields.io/github/stars/fontnelle/dudu?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/fontnelle/dudu/releases"><img src="https://img.shields.io/github/v/release/fontnelle/dudu?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/fontnelle/dudu/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/fontnelle/dudu/ci.yml?branch=main&label=tests&style=flat-square" alt="Tests"></a>
  <a href="#quick-start"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square" alt="Platform"></a>
</div>

<p align="center">
  <img src="./docs/img/backup.svg" alt="dudu backup: 9 tools collected, encrypted and saved to a local folder, iCloud Drive and Apple Notes" width="790" />
</p>

## Features

- **Everything you installed from the terminal**: Homebrew, apt/dnf/pacman, Node versions, global npm/pnpm/yarn/bun packages, pyenv/pipx/uv, gems, cargo, go tools, VS Code and Cursor extensions
- **Your terminal, as it was**: zsh, Oh My Zsh and plugins, Powerlevel10k/Starship, Terminal.app and iTerm2 profiles, Ghostty, Kitty, WezTerm, Nerd Fonts, git and SSH config
- **Saved where you already are**: a local folder, iCloud Drive, Google Drive and Apple Notes, several at once
- **Secrets stay home**: tokens in your dotfiles are masked, key files are never copied, and `dudu secrets` moves keys out of your `.zshrc`
- **Encrypted if you want**: AES-256 with a password kept in your Keychain
- **Safe to restore**: a backup is treated as untrusted, checked against its checksums, and never overwrites a file without keeping a copy
- **Runs by itself**: a daily backup with `dudu schedule on`
- **Speaks your language**: English, Português (Brasil) and Español, picked from your system
- **Pure bash, no dependencies**: works with the bash 3.2 that ships with macOS

## Quick Start

**Install via Homebrew**

```bash
brew install fontnelle/tap/dudu
```

**Or via script**

```bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash
```

The script verifies the release against its `SHA256SUMS`. Options: `| bash -s -- 0.1.0` for a version, `| bash -s -- --prefix ~/.local/bin` for where the command goes.

**Run**

```bash
dudu                 # interactive menu
dudu backup          # save everything to your destinations
dudu restore         # on the new machine: reinstall everything
dudu status          # what changed since the last backup
dudu outdated        # updates for brew, npm, pip, gems, Node LTS... then update all or pick
dudu secrets         # keys found in your config files, and moving them to ~/.secrets
dudu schedule on     # a backup every day (12:30, or: dudu schedule on 08:00)
dudu config          # destinations, language, encryption, schedule
```

Every command takes `--dry-run` and `--only brew,node,...`. `restore` also takes `--from <machine>` (a backup from another computer), `--file <folder>` (a backup copied by hand) and `--yes`. `--debug` traces every step into `~/.cache/dudu/dudu.log` (needs bash 4.1+).

## New machine, step by step

```bash
brew install fontnelle/tap/dudu   # or the script, on a Mac without Homebrew yet
dudu config                       # the same destination as the old machine
dudu restore --dry-run            # see what will happen
dudu restore
```

The restore runs in order: Homebrew first (which brings pyenv, go, fonts...), then the shell and git config, Node versions, global packages, editors and macOS preferences. Every step is idempotent: what is already installed is skipped, and a file that differs is kept as `<file>.dudu-bak`.

## From a Mac to Linux

A backup made on a Mac restores on Linux too, as far as Linux allows. Google Drive is the bridge: the Mac writes to it with Drive for desktop, Linux reads it through `rclone`.

```bash
# On the Mac: add Google Drive to the destinations, then back up
dudu config
dudu backup

# On Linux
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash
dudu config                     # check Google Drive: dudu installs rclone and signs you in
dudu restore --dry-run --from <mac name>
dudu restore --from <mac name>
```

- **Homebrew becomes the system's packages.** Formulae are installed with apt, dnf or pacman under the same name when the repositories have it (`fd` becomes `fd-find`, `node` becomes `nodejs`...). Known casks come from the system or from Flathub (VS Code, Chrome, Slack, Spotify, Obsidian...). Homebrew itself is not installed. If it is already on the machine, formulae with no native package go to it.
- **Settings follow the paths of Linux.** VS Code and Cursor settings move from `~/Library/Application Support` to `~/.config`, and so does Ghostty's.
- **Before anything is installed, the plan lists what is left out:** Mac App Store apps, casks with no Linux build, macOS preferences and Terminal.app/iTerm2 profiles.

The names that differ are in [`lib/data/brew-linux.map`](lib/data/brew-linux.map). A missing app is one line away.

## Where backups go

| Destination | Where | Notes |
| --- | --- | --- |
| Local folder | `~/dudu-backups` or any folder | Default |
| iCloud Drive | `iCloud Drive/dudu` | macOS |
| Google Drive | `Google Drive/My Drive/dudu` | Drive for desktop on macOS. On Linux, a synced folder (`dudu config set gdrive_path ~/GoogleDrive/dudu`) or `rclone` (`dudu config set rclone_remote gdrive:dudu`) |
| Apple Notes | the note `dudu backup - <machine>` in the `dudu` folder | macOS. A readable summary plus the whole backup embedded. The first save asks for permission to control Notes |

Pick **one or more** with `dudu config` or `dudu config set destination icloud,notes`. Each backup goes to all of them, and one failing does not stop the others. `restore` and `status` read the newest backup found across them. Folders keep the latest 5 backups per machine (`dudu config set keep 10`).

## What gets backed up

| Collector | Saves | Restores with |
| --- | --- | --- |
| `brew` | Brewfile (formulae, casks, taps, Mac App Store) | `brew bundle install` (installs Homebrew if needed). On Linux, a Mac's Brewfile becomes apt/dnf/pacman and Flathub packages |
| `syspkgs` | manually installed apt/dnf/pacman packages, flatpak, snap | the system package manager |
| `shell` | `.zshrc`, `.zprofile`, `.bashrc`, `.p10k.zsh`, `starship.toml`, tmux, vim, fish, nvim, Oh My Zsh custom plugins/themes (as git URLs) | copies files, installs Oh My Zsh, clones plugins |
| `git` | `.gitconfig`, global gitignore, `~/.ssh/config`, gh config | copies files |
| `terminal` | Terminal.app and iTerm2 profiles, Ghostty, Alacritty, Kitty, WezTerm, the list of Nerd Fonts | `defaults import`, copies files |
| `node` | nvm (or fnm/volta) versions and the default | installs nvm, `nvm install` each version |
| `npm` `pnpm` `yarn` `bun` | global packages (per Node version with nvm), `.npmrc` | `npm install -g` ... |
| `python` | pyenv versions, pipx and uv tools, `pip --user` | `pyenv install`, `pipx install`, `uv tool install` |
| `ruby` `cargo` `go` | gems/rbenv, `cargo install` crates, `go install` tools | the same tools |
| `vscode` `cursor` | extensions, settings, keybindings, snippets | `code --install-extension` |
| `macos` | a curated set of Dock, Finder, keyboard and screenshot preferences | `defaults write` |

Skip collectors with `dudu config set exclude macos,ruby`, or keep only some with `dudu config set include brew,node,shell`.

## Security

**Secrets stay on your machine**

- Values that look like secrets (`TOKEN=`, `_authToken=`, `password:`, `api_key`, `Bearer …`, `https://user:pass@`, `ghp_…`, `sk-…`, `npm_…`, `AKIA…`, JWTs, private key blocks) become `<redacted-by-dudu>` in the backup. References like `$(security …)` or `$MY_VAR` are kept.
- Key files are never copied: `~/.ssh/id_*`, `~/.gnupg`, `~/.aws/credentials`, `~/.netrc`, `~/.kube/config`, `~/.docker/config.json`, `gh` tokens, `~/.secrets`. dudu lists the ones it found so you can move them yourself.
- A file dudu cannot check for secrets is left out of the backup, never copied as is.
- Each backup ends with the keys it masked: file, line and name, never the value. `dudu secrets` offers to move the `export NAME=…` lines of your shell files to `~/.secrets` (mode 600), which your `.zshrc` then loads from the same spot.
- On restore, a file whose only difference is the masked secret is left alone, so restoring on the same machine never wipes your tokens.

**Encryption**

`dudu config set encrypt on` asks for a password (12+ characters) and keeps it in the macOS Keychain (on Linux, `secret-tool` or `~/.config/dudu/key` with mode 600). Each backup then becomes one `backup.enc` (AES-256-CBC, PBKDF2 with 200,000 rounds, via `openssl`) plus a MAC checked before anything is decrypted. Only `manifest.json` (machine name, date, which tools) and a generic `RESTORE.md` stay readable. On a new machine, `dudu restore` asks for the password. **Without it the backup cannot be restored**, so keep it in your password manager.

**What a backup can and cannot do to you**

Anyone with access to the iCloud or Google Drive account can change a backup folder there, so dudu treats it as untrusted on restore:

- package names are checked (no options, URLs or paths) before they reach `apt`, `brew`, `npm`, `pip`...;
- a Brewfile keeps only `tap`/`brew`/`cask`/`mas`/`vscode` lines, so it cannot run Ruby;
- files go back only to the paths each tool backs up, never to `~/.ssh/authorized_keys`, `~/Library/LaunchAgents` or `~/.secrets`, and never through a symlink;
- macOS preferences are limited to a known list, and every overwritten file is kept as `.dudu-bak`.

With encryption on, the MAC check comes first: a changed backup is refused before anything runs.

## Reliability

- Every backup carries a `SHA256SUMS`. Saves go to a `.partial` folder, are checked, then renamed, so an interrupted save never becomes the backup restore uses. Notes are read back and checked, and the previous note is kept as "(previous)".
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

`dudu schedule on [HH:MM]` adds a daily backup: a LaunchAgent on macOS, a systemd user timer on Linux. It runs without a terminal, so it uses the stored backup password, and a failure shows a notification. If you use Apple Notes, run one backup by hand first so macOS can ask for the permission. `dudu schedule status` shows it, `dudu schedule off` removes it.

## Language

dudu speaks English, Português (Brasil) and Español. It follows your system language (`LANG`, or System Settings on macOS) with nothing to set up, and the first run says which one it picked.

```bash
dudu config set language es      # en, pt-BR, es, or auto to follow the system again
DUDU_LANG=en dudu status         # one command in another language
```

Or from the menu: **Settings › Language**. A backup's `RESTORE.md` (and its Apple Notes note) is written in the language of the machine that made it. Tab completion descriptions in zsh follow the same setting.

## Shell completion and highlighting

```bash
dudu completion zsh > "${fpath[1]}/_dudu"                       # zsh tab completion
echo 'eval "$(dudu completion bash)"' >> ~/.bashrc              # bash tab completion
echo "source $(dudu completion highlight --path)" >> ~/.zshrc   # zsh highlighting
```

Homebrew installs the tab completion for you. With [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) or [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting), `dudu backup` shows the subcommand in yellow while you type, and a typo like `dudu bakcup` in red.

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

Code must run on bash 3.2 (the macOS default): no associative arrays, no `mapfile`, no `${var,,}`, and `${VAR}` before any non-ASCII character. Messages are written in English as `t "text %s" "$value"` (or `tn` for plurals) and translated in `lib/i18n/pt-BR.sh` and `lib/i18n/es.sh`; `make check` fails when a message is missing from a catalog. CI runs the tests on macOS, bash 3.2, Ubuntu, Fedora and Arch.

## License

MIT.
