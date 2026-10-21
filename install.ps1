# dudu installer for Windows, from PowerShell:
#   irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
# dudu runs in Git Bash: this installs Git for Windows when it is missing (with winget), runs
# install.sh in Git Bash, and adds a dudu command for PowerShell and cmd.
# A version or the development branch: $env:DUDU_VERSION = "0.1.0" (or "windows") first.

$ErrorActionPreference = "Stop"
$Branch = "windows"
$Repo = "fontnelle/dudu"

function Step($m) { Write-Host "- $m" -ForegroundColor Blue }
function Ok($m) { Write-Host "OK $m" -ForegroundColor Green }
# throw, not exit: through irm | iex, exit would close the user's PowerShell window.
function Die($m) { Write-Host "x $m" -ForegroundColor Red; throw "dudu was not installed" }

function Find-GitBash {
  $candidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
  )
  $git = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($git) { $candidates += (Join-Path (Split-Path (Split-Path $git.Source)) "bin\bash.exe") }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}

$bash = Find-GitBash
if (-not $bash) {
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Die "dudu needs Git for Windows (Git Bash). Install it from https://git-scm.com/download/win and run this again."
  }
  Step "Installing Git for Windows (dudu runs in Git Bash)"
  winget install --id Git.Git --exact --silent --accept-source-agreements --accept-package-agreements
  $bash = Find-GitBash
  if (-not $bash) { Die "Git for Windows did not install. Install it from https://git-scm.com/download/win and run this again." }
}
Ok "Git Bash: $bash"

# install.sh of the same branch, saved to a file and run whole by Git Bash.
$installer = Join-Path $env:TEMP "dudu-install-$PID.sh"
Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$Repo/$Branch/install.sh" -OutFile $installer
$bashArgs = @(($installer -replace '\\', '/'))
if ($env:DUDU_VERSION) { $bashArgs += $env:DUDU_VERSION }
& $bash $bashArgs
$rc = $LASTEXITCODE
Remove-Item $installer -ErrorAction SilentlyContinue
if ($rc -ne 0) { Die "install.sh stopped (exit code $rc)" }

# dudu.cmd runs dudu in Git Bash from PowerShell, cmd and the Run dialog.
$binDir = Join-Path $env:LOCALAPPDATA "dudu\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$lib = (Join-Path $env:USERPROFILE ".local\share\dudu\dudu") -replace '\\', '/'
Set-Content -Encoding ASCII -Path (Join-Path $binDir "dudu.cmd") -Value "@`"$bash`" `"$lib`" %*"

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not (($userPath -split ";") -contains $binDir)) {
  [Environment]::SetEnvironmentVariable("Path", (($userPath.TrimEnd(";"), $binDir) -join ";").TrimStart(";"), "User")
  $env:Path = "$env:Path;$binDir"
  Ok "Added $binDir to your PATH (new terminals pick it up)"
}
Write-Host ""
Write-Host "Run " -NoNewline; Write-Host "dudu" -ForegroundColor Green -NoNewline
Write-Host " to start, or " -NoNewline; Write-Host "dudu backup" -ForegroundColor Green -NoNewline
Write-Host " to save your setup now."
