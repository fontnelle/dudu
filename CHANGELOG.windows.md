# Changelog (Windows)

The Windows edition of dudu lives on the `windows` branch and is released as `win-vX.Y.Z`.
Each release on GitHub takes its notes from here: add a `## win-vX.Y.Z · Title` section before tagging.
The install commands and the changelog link are added by the release workflow.
The macOS and Linux edition has its own [CHANGELOG.md](CHANGELOG.md).

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
