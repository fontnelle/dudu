# Changelog

Each release on GitHub takes its notes from here: add a `## vX.Y.Z · Title` section before tagging.
The install commands and the changelog link are added by the release workflow.

## v0.2.2 · dudu update with Homebrew

### Fixed

- **`dudu update` really updates a Homebrew install.** Homebrew reads a tap's new formulas at most once a day, so `brew upgrade dudu` right after a release said the old version was current. `dudu update` now runs `brew update` first, and the "new version" notice suggests `brew update && brew upgrade dudu`.

## v0.2.1 · Scheduled backups after brew upgrade

### Fixed

- **Scheduled backups survive `brew upgrade`.** With a Homebrew install, `dudu schedule on` pointed the daily job at that version's Cellar folder, which the next upgrade removes, so the backup silently stopped. It now uses Homebrew's stable `opt/dudu` path.

If you installed with Homebrew and turned the schedule on, run `dudu schedule on` once more after updating.

## v0.2.0 · English, Português, Español

dudu now speaks **English, Português (Brasil) and Español**.

### New

- **Picked from your system, nothing to set up.** dudu follows `LANG` (or System Settings on macOS, which also covers scheduled backups), and the first run says which language it picked.
- **Change it any time:** `dudu config set language es` (`en`, `pt-BR`, `es` or `auto`), **Settings › Language** in the menu, or `DUDU_LANG=en dudu status` for one command.
- **Settings is now a menu:** destinations, language, encryption and the daily schedule in one place.
- **Translated everywhere you read it:** menus, messages, `--help`, the backup's `RESTORE.md` and Apple Notes note, and zsh tab completion descriptions.
- **README in Spanish:** [README.es.md](https://github.com/fontnelle/dudu/blob/main/README.es.md).

### Fixed

- Columns stay aligned with accented text.
- A few checks could fail at random (`printf | grep -q` under `pipefail`), including picking the machine to restore.

## v0.1.0 · First release

First release: back up your whole dev setup in one command and put it back on a new machine in another.

### Highlights

- **Everything you installed from the terminal:** Homebrew, apt/dnf/pacman, Node versions and global packages, pyenv/pipx/uv, gems, cargo, go tools, VS Code and Cursor extensions.
- **Your terminal, as it was:** zsh, Oh My Zsh and plugins, Powerlevel10k/Starship, Terminal.app, iTerm2, Ghostty, Kitty, WezTerm, Nerd Fonts, git and SSH config.
- **Saved where you already are:** a local folder, iCloud Drive, Google Drive and Apple Notes, several at once.
- **Secrets stay home:** tokens are masked, key files are never copied, `dudu secrets` moves keys out of your dotfiles.
- **Optional encryption:** AES-256 with a password kept in your Keychain.
- **Safe restore:** backups are checked against their checksums and treated as untrusted; nothing is overwritten without a copy.
- **Daily backups** with `dudu schedule on`, and `dudu outdated` to update your tools.
- **Pure bash**, works with the bash 3.2 that ships with macOS. Tested on macOS, Ubuntu, Fedora and Arch.
