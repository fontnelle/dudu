# Changelog (Windows)

The Windows edition of dudu lives on the `windows` branch and is released as `win-vX.Y.Z`.
Each release on GitHub takes its notes from here: add a `## win-vX.Y.Z · Title` section before tagging.
The install commands and the changelog link are added by the release workflow.
The macOS and Linux edition has its own [CHANGELOG.md](CHANGELOG.md).

## win-v0.2.0 · Easy to install, easy to use

### Added

- **An installer to double-click.** Download `dudu-setup.cmd` from the release, double-click it, and it runs the installer: no PowerShell window to open, no command to paste.
- **dudu in the Start menu.** The installer adds a dudu entry that opens the menu in Windows Terminal, or in Git Bash's own window where there is none. Backup, restore and settings work with the arrow keys and Enter, with nothing to type.
- **`dudu doctor`** checks Git Bash, the package managers, the `dudu` command in PowerShell and cmd, the Credential Manager, your destinations, encryption, the schedule and the terminal, and says in plain words what to do about each thing that is missing.
- **`dudu uninstall`** removes the command, the Start menu entry, the PATH entry and the scheduled backup. It asks before deleting your settings and the stored password (`--purge` does it without asking) and never touches your backups.
- **OneDrive is a destination**: the folder the OneDrive app syncs, which Windows comes with.
- **scoop**: `scoop bucket add fontnelle https://github.com/fontnelle/scoop-bucket`, then `scoop install dudu`. `dudu update` then runs `scoop update dudu`.
- **Tab completion in PowerShell**: `dudu completion powershell`.
- **A Windows without winget** gets Git for Windows from Git's own releases, installed for the current user, with no administrator.

### Changed

- **The `dudu` command for PowerShell and cmd is now a `dudu.cmd` inside dudu's own folder**, which finds Git Bash and dudu when it runs. No folder is written into it any more, so it keeps working when Git moves or the user folder has an accent. The installer moves the PATH entry and removes the old `%LOCALAPPDATA%\dudu` folder.
- `install.ps1` runs the `install.sh` of the release it installs, not the one at the tip of the branch; it speaks English, Português and Español; it changes the user PATH in the registry without expanding the `%VARIABLES%` already in it; and it turns TLS 1.2 on for older Windows PowerShell.
- While dudu runs from PowerShell or cmd, the console is set to UTF-8 (and put back afterwards), so names with accents coming from Windows tools read right.
- The spinner uses plain characters in the old Windows console, which has no braille.

### Not tested on a real machine

Tested on GitHub's Windows runners only. No test covers these: the Start menu entry actually opening (it is created and its target checked), Windows' "came from the internet" warning on `dudu-setup.cmd`, the old Windows 10 console, and installing Git on a machine that has none (with winget, or from Git's releases): GitHub's runners already have it.

## win-v0.1.1 · Fixes from a full review

### Fixed

- **Go tools are backed up again.** A Windows `GOPATH` (`C:\Users\you\go`) was read as a Unix one, so `go install`ed tools were never saved.
- **A folder can be typed the Windows way.** `C:\Users\you\OneDrive\dudu`, `D:\Backups` and a path pasted from Explorer with its quotes are accepted for the local folder and `gdrive_path`; before, only `/c/...` and `~/...` were.
- **PowerShell profiles are saved when Documents is in OneDrive**, the default on Windows 11. They are read from wherever Documents really is, and restored there.
- **Restoring a Mac's backup:** global npm packages are installed (they were skipped as "node is not installed"); what winget and scoop install is usable by the tools restored next, in the same run; with fnm, node is put in the PATH and you are told how to keep it there; Oh My Zsh is no longer installed where there is no zsh; and the Mac's `.bashrc`, `.bash_profile` and `.profile` are listed and set aside, not written over Git Bash's.
- **The scheduled backup runs on battery, and later the same day when the computer was off or asleep at its time.** It also works for a user folder with an accent (`C:\Users\João`), and on a Windows without the script host.
- **`dudu update` while dudu is open** no longer fails on the folder Windows keeps in use, and run from PowerShell or cmd it no longer leaves a second `dudu` in `~/.local/bin`.
- **The `dudu` command in PowerShell and cmd works for a user folder with an accent**, and the installer no longer stops on an empty user PATH.
- **Chocolatey outside an administrator terminal** is not started: dudu says how to open one. Before a restore, it says that Windows may ask for permission in a window of its own.
- When the Credential Manager cannot keep the backup password, dudu says that it went to a file.
- `RESTORE.md` gives the install command of each system; it only had the macOS and Linux one.
- pyenv-win's versions are read (their Windows line ends made each one "suspicious").
- Messages no longer point Windows users at a Brewfile, and Apple Notes is no longer listed as a destination.

### Added

- pip's `%APPDATA%\pip\pip.ini` and the GitHub CLI's `%APPDATA%\GitHub CLI\config.yml` are backed up.
- `install.sh --source <folder>` installs a copy of dudu already on the computer.

### Changed

- Checksums use `sha256sum`, much faster in Git Bash than `shasum`.

### Not tested on a real machine

These were tested on GitHub's Windows runners only, never on a real machine: a laptop actually running on battery, the old Windows 10 console, and a Windows without `wscript.exe` (the scheduled backup then starts in a hidden console, a path no test runs).

## win-v0.1.0 · dudu for Windows

### Added

- **dudu runs on Windows, in Git Bash.** `install.ps1` installs Git for Windows when it is missing, installs dudu and adds a `dudu` command to PowerShell and cmd. In Git Bash, `install.sh` works as on macOS and Linux.
- **winget, scoop and Chocolatey packages** are backed up and restored, each by its own collector. `dudu outdated` lists their updates.
- **Windows Terminal settings**, PowerShell profiles, Git Bash's `.minttyrc` and Neovim's `AppData\Local\nvim` are backed up with the rest of the shell and terminal setup.
- **VS Code and Cursor settings** move between `AppData\Roaming` (Windows), `~/Library/Application Support` (macOS) and `~/.config` (Linux).
- **Google Drive for desktop** is found on its drive letter (`G:\My Drive`) or its mirrored folder, and `dudu config gdrive` installs rclone with winget or scoop. **iCloud for Windows** (`iCloudDrive`) is a destination too.
- **The backup password is kept in the Windows Credential Manager.**
- **`dudu schedule on`** creates a daily Task Scheduler task that runs hidden, and a failed scheduled backup shows a Windows notification.
- **A Mac's backup restores on Windows:** Homebrew formulas and casks become winget packages, or scoop ones when winget has none; what has no equivalent is listed before restoring. nvm becomes nvm-windows or fnm, and rustup and bun are installed with winget.
- **A Windows backup restores on macOS and Linux:** editor settings move to their place there, and what only exists on Windows is listed and set aside.
- `dudu update` follows the `win-v` releases, never the macOS/Linux ones.
