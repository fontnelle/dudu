# Changelog

Each release on GitHub takes its notes from here: add a `## vX.Y.Z · Title` section before tagging.
The install commands and the changelog link are added by the release workflow.

## Unreleased · Google Drive in four steps

### Added

- **`dudu config gdrive`: Google Drive without Drive for desktop, on macOS and Linux.** It walks through four steps: rclone (installed if missing), the folder, the Google sign-in and the checks. Checking Google Drive in `dudu config` runs the same steps when no Drive for desktop folder is found.
- **The least access by default.** Pressing Enter makes a `dudu` folder in My Drive with `drive.file` access: dudu sees only the files it creates. Pasting a folder link uses that folder instead. Only `https://drive.google.com/drive/folders/…` links are taken; short links and look-alike sites are refused.
- **Checks before the first backup.** A test file is written, read back and removed. rclone's config, which holds the Google token, is set to be readable only by you. dudu offers to turn on encryption when it is off, and lists the machines already backed up in the folder.
- **dudu keeps its own rclone remote** (`dudu-gdrive`), so remotes you already have are never changed. If a step fails, nothing is saved and the previous settings stay.
- **`dudu` asks to update when a new version is out**, as Oh My Zsh does. Enter updates and reopens dudu on the new version. `n` keeps the current one, and dudu does not ask again until the next release.

## v0.4.0 · From a Mac to Linux

### Added

- **Restore a Mac's backup on Linux.** Homebrew formulae become apt, dnf or pacman packages, and known casks come from the system or Flathub (VS Code, Chrome, Slack...), without installing Homebrew. Editor and Ghostty settings move to `~/.config`. The plan lists what is left out before anything is installed: App Store apps, casks with no Linux build, macOS preferences, Terminal.app/iTerm2 profiles. The names that differ are in `lib/data/brew-linux.map`.
- **Google Drive on Linux, set up by `dudu config`.** Checking Google Drive installs rclone, connects your Google account and points it at the same `dudu` folder the Mac writes to. It then lists the machines it found there.

### Changed

- **Tools of the other OS are listed, not restored.** macOS preferences on Linux, or Linux packages on a Mac, show as "macOS only, not restored here" instead of "not on this machine". They are not checked and not restored with `-y`.
- **The Nerd Fonts hint on Linux** points to `~/.local/share/fonts` instead of a Homebrew cask.

### Fixed

- **Google Drive through rclone falls back to an older backup** when the newest one fails its checksums, as the folder destinations already did.

## v0.3.0 · Restore shows what it will do

### Changed

- **Restore looks like backup, in three steps.** *Source* lists every destination with the date of its backup and marks the one being restored. *Comparing* checks each tool against this machine. *Restoring* reinstalls only what you picked.
- **Only what differs.** Tools that already match the backup are left alone. If nothing differs, restore says so and stops. `--only` still restores what you name.
- **What will be done, before it is done.** Each difference becomes an action: "install v20.19.6", "change version manager: system → nvm", "replace ~/.zshrc". Press Enter to restore all of it, or E to pick tools from a checklist. With `-y`, it restores the tools that differ.
- **A line per tool at the end**, restored or not, after the installers' output.
- **`dudu status` names things as you know them:** `iterm2 (cask)` instead of "Brewfile changed", and "version manager: nvm → system".

### Fixed

- **A long spinner line no longer floods the screen.** On a narrow terminal, "Fetching the newest backup…" wrapped and was redrawn over and over. Spinner labels are now cut to the terminal width.

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
