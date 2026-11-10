# dudu installer for Windows, from PowerShell:
#   irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
# dudu runs in Git Bash: this installs Git for Windows when it is missing, installs dudu with
# install.sh, adds the dudu command to PowerShell and cmd, and a dudu entry to the Start menu.
# A version or the development branch: $env:DUDU_VERSION = "0.2.0" (or "windows") first.
# A copy of dudu already on this computer: $env:DUDU_SOURCE = "C:\path\to\dudu" first.
#
# Keep this file free of the letters whose UTF-8 bytes Windows PowerShell 5.1 reads as quotes
# when it takes the file for ANSI (N-tilde and O with grave, acute or circumflex in capitals,
# curly quotes, long dashes): make lint checks it.

$ErrorActionPreference = "Stop"
$Branch = "windows"
$Repo = "fontnelle/dudu"
$TagPrefix = "win-v"

# Messages in the language of Windows, as dudu itself does.
$Lang = "en"
try {
  $ui = (Get-UICulture).Name
  if ($ui -like "pt*") { $Lang = "pt" } elseif ($ui -like "es*") { $Lang = "es" }
} catch {}
$Messages = @{
  NeedGit = @{
    en = "dudu needs Git for Windows (Git Bash). Install it from https://git-scm.com/download/win and run this again."
    pt = "O dudu precisa do Git for Windows (Git Bash). Instale por https://git-scm.com/download/win e rode isto de novo."
    es = "dudu necesita Git for Windows (Git Bash). Instala desde https://git-scm.com/download/win y ejecuta esto de nuevo."
  }
  InstallingGit = @{
    en = "Installing Git for Windows (dudu runs in Git Bash). Windows may ask for permission."
    pt = "Instalando o Git for Windows (o dudu roda no Git Bash). O Windows pode pedir permissão."
    es = "Instalando Git for Windows (dudu se ejecuta en Git Bash). Windows puede pedir permiso."
  }
  DownloadingGit = @{
    en = "Downloading Git for Windows from its official releases"
    pt = "Baixando o Git for Windows das releases oficiais"
    es = "Descargando Git for Windows de sus releases oficiales"
  }
  NoRelease = @{
    en = "Could not find the latest release (offline, or GitHub's rate limit). Try again in a few minutes."
    pt = "Não deu para achar a última versão (sem internet, ou limite do GitHub). Tente de novo em alguns minutos."
    es = "No se pudo encontrar la última versión (sin conexión, o límite de GitHub). Inténtalo en unos minutos."
  }
  InstallFailed = @{
    en = "The installation stopped (exit code {0})"
    pt = "A instalação parou (código {0})"
    es = "La instalación se detuvo (código {0})"
  }
  NotInstalled = @{ en = "dudu was not installed"; pt = "o dudu não foi instalado"; es = "dudu no se instaló" }
  PathAdded = @{
    en = "The dudu command works in PowerShell and cmd (in terminals opened from now on)"
    pt = "O comando dudu funciona no PowerShell e no cmd (nos terminais abertos a partir de agora)"
    es = "El comando dudu funciona en PowerShell y cmd (en las terminales abiertas desde ahora)"
  }
  Shortcut = @{
    en = "dudu is in the Start menu"
    pt = "O dudu está no Menu Iniciar"
    es = "dudu está en el menú Inicio"
  }
  NoShortcut = @{
    en = "Could not add dudu to the Start menu (the dudu command works all the same)"
    pt = "Não deu para pôr o dudu no Menu Iniciar (o comando dudu funciona do mesmo jeito)"
    es = "No se pudo añadir dudu al menú Inicio (el comando dudu funciona igual)"
  }
  Done1 = @{
    en = "Done. Two ways to use dudu:"
    pt = "Pronto. Dois jeitos de usar o dudu:"
    es = "Listo. Dos formas de usar dudu:"
  }
  DoneMenu = @{
    en = "  - open the Start menu and click dudu (arrows and Enter, nothing to type)"
    pt = "  - abra o Menu Iniciar e clique em dudu (setas e Enter, sem digitar nada)"
    es = "  - abre el menú Inicio y haz clic en dudu (flechas y Enter, sin escribir nada)"
  }
  DoneCmd = @{
    en = "  - or type dudu in a new PowerShell window"
    pt = "  - ou digite dudu numa janela nova do PowerShell"
    es = "  - o escribe dudu en una ventana nueva de PowerShell"
  }
}
function Msg($key) { $m = $Messages[$key]; if ($m[$Lang]) { $m[$Lang] } else { $m["en"] } }

function Step($m) { Write-Host "- $m" -ForegroundColor Blue }
function Ok($m) { Write-Host "OK $m" -ForegroundColor Green }
function Note($m) { Write-Host "!  $m" -ForegroundColor Yellow }
# throw, not exit: through irm | iex, exit would close the user's PowerShell window.
function Die($m) { Write-Host "x $m" -ForegroundColor Red; throw (Msg NotInstalled) }

# Older Windows PowerShell starts without TLS 1.2, which GitHub requires.
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

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

# Git for Windows from its own releases, for a Windows without winget or where winget failed.
# Its installer needs no administrator: without one it installs for this user only.
function Install-GitDirect {
  Step (Msg DownloadingGit)
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "64-bit" }
  $release = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/git-for-windows/git/releases/latest"
  $asset = $release.assets | Where-Object { $_.name -like "Git-*-$arch.exe" } | Select-Object -First 1
  if (-not $asset) { return }
  $setup = Join-Path $env:TEMP $asset.name
  Invoke-WebRequest -UseBasicParsing $asset.browser_download_url -OutFile $setup
  $setupArgs = @("/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/SUPPRESSMSGBOXES")
  Start-Process -FilePath $setup -ArgumentList $setupArgs -Wait
  Remove-Item $setup -ErrorAction SilentlyContinue
}

function Install-Git {
  Step (Msg InstallingGit)
  if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    try {
      winget install --id Git.Git --exact --silent --accept-source-agreements --accept-package-agreements | Out-Host
    } catch {}
    if (Find-GitBash) { return }
  }
  try { Install-GitDirect } catch { Note $_.Exception.Message }
}

# The newest release of the Windows edition (the repository's "latest" is the macOS/Linux one).
function Get-LatestVersion {
  $releases = Invoke-RestMethod -UseBasicParsing "https://api.github.com/repos/$Repo/releases?per_page=50"
  foreach ($r in $releases) {
    if ($r.tag_name -like "$TagPrefix*" -and -not $r.prerelease -and -not $r.draft) { return $r.tag_name.Substring($TagPrefix.Length) }
  }
  return $null
}

# The user's PATH, read and written as the registry keeps it: going through .NET would expand
# every %VARIABLE% in it for good.
function Set-UserPath($add, $remove) {
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
  $raw = [string]$key.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
  if ($raw) { $kind = $key.GetValueKind("Path") }
  $drop = @($add) + @($remove) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd("\") }
  $parts = @($raw -split ";" | Where-Object { $_ -and ($drop -notcontains $_.TrimEnd("\")) })
  $new = (@($parts) + @($add) | Where-Object { $_ }) -join ";"
  $changed = $new -ne $raw
  if ($changed) {
    $key.SetValue("Path", $new, $kind)
    # Setting any user variable tells the open programs that the environment changed.
    [Environment]::SetEnvironmentVariable("DUDU_PATH_REFRESH", $null, "User")
  }
  $key.Close()
  return $changed
}

# A dudu entry in the Start menu, opening the menu in Windows Terminal, or in Git Bash's own
# window where there is none: both show dudu's symbols right, which the old console may not.
function Add-Shortcut($cmdFile, $bash) {
  $programs = [Environment]::GetFolderPath("Programs")
  $link = Join-Path $programs "dudu.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $s = $shell.CreateShortcut($link)
  $gitRoot = Split-Path (Split-Path $bash)
  $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
  $mintty = Join-Path $gitRoot "usr\bin\mintty.exe"
  if ($wt) {
    $s.TargetPath = $wt.Source
    $s.Arguments = "--title dudu cmd.exe /c `"$cmdFile`""
  } elseif (Test-Path $mintty) {
    $s.TargetPath = $mintty
    $s.Arguments = "-t dudu -e `"$bash`" `"" + ((Join-Path (Split-Path $cmdFile) "dudu") -replace '\\', '/') + "`""
  } else {
    $s.TargetPath = $cmdFile
  }
  $s.WorkingDirectory = $env:USERPROFILE
  $s.Description = "dudu: backup and restore of your dev setup"
  $icon = Join-Path $gitRoot "mingw64\share\git\git-for-windows.ico"
  if (Test-Path $icon) { $s.IconLocation = $icon }
  $s.Save()
}

# For the tests: the functions above, without installing anything.
if ($env:DUDU_PS1_FUNCTIONS_ONLY) { return }

$bash = Find-GitBash
if (-not $bash) {
  Install-Git
  $bash = Find-GitBash
  if (-not $bash) { Die (Msg NeedGit) }
}
Ok "Git Bash: $bash"

# install.sh of the release being installed (not of the branch, which may be ahead of it),
# saved to a file and run whole by Git Bash.
if ($env:DUDU_SOURCE) {
  $src = (Resolve-Path $env:DUDU_SOURCE).Path -replace '\\', '/'
  & $bash "$src/install.sh" --source $src
  $rc = $LASTEXITCODE
} else {
  $version = $env:DUDU_VERSION
  if (-not $version) {
    try { $version = Get-LatestVersion } catch { $version = $null }
    if (-not $version) { Die (Msg NoRelease) }
  }
  $version = $version -replace '^v', ''
  $ref = if ($version -eq $Branch -or $version -eq "main") { $Branch } else { "$TagPrefix$version" }
  $installer = Join-Path $env:TEMP "dudu-install-$PID.sh"
  Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/$Repo/$ref/install.sh" -OutFile $installer
  & $bash ($installer -replace '\\', '/') $version
  $rc = $LASTEXITCODE
  Remove-Item $installer -ErrorAction SilentlyContinue
}
if ($rc -ne 0) { Die ((Msg InstallFailed) -f $rc) }

# Where install.sh put dudu, asked to Git Bash (its HOME is not always the Windows profile).
$prevEncoding = [Console]::OutputEncoding
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$libDir = (& $bash -c 'cygpath -w "${XDG_DATA_HOME:-$HOME/.local/share}/dudu"' | Select-Object -First 1)
try { [Console]::OutputEncoding = $prevEncoding } catch {}
if (-not $libDir -or -not (Test-Path (Join-Path $libDir "dudu"))) {
  $libDir = Join-Path $env:USERPROFILE ".local\share\dudu"
}
$cmdFile = Join-Path $libDir "dudu.cmd"
if (-not (Test-Path $cmdFile)) {
  # Releases before 0.2.0 have no dudu.cmd of their own.
  Set-Content -Encoding ASCII -Path $cmdFile -Value @(
    "@echo off", "setlocal", 'set "DUDU_DIR=%~dp0"', "`"$bash`" `"%DUDU_DIR:\=/%dudu`" %*"
  )
}

# dudu.cmd's folder goes in the user's PATH; the folder 0.1 used for it goes away.
$oldBin = Join-Path $env:LOCALAPPDATA "dudu\bin"
if (Set-UserPath $libDir $oldBin) { Ok (Msg PathAdded) }
if (-not (($env:Path -split ";") -contains $libDir)) { $env:Path = "$env:Path;$libDir" }
if (Test-Path $oldBin) { Remove-Item -Recurse -Force (Split-Path $oldBin) -ErrorAction SilentlyContinue }

try { Add-Shortcut $cmdFile $bash; Ok (Msg Shortcut) } catch { Note (Msg NoShortcut) }

Write-Host ""
Write-Host (Msg Done1) -ForegroundColor Green
Write-Host (Msg DoneMenu)
Write-Host (Msg DoneCmd)
