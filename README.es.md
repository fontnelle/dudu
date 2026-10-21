<div align="center">
  <h1>dudu para Windows</h1>
  <p><b>Respalda todo tu entorno de desarrollo con un comando y recupéralo en una máquina nueva con otro. Paquetes, runtimes, dotfiles y terminal, en Windows.</b></p>
  <p><a href="README.md">English</a> · <a href="README.pt-BR.md">Português</a> · Español</p>
  <p>¿Usas macOS o Linux? Usa la <a href="https://github.com/fontnelle/dudu/tree/main">rama <code>main</code></a>.</p>
  <a href="https://github.com/fontnelle/dudu/stargazers"><img src="https://img.shields.io/github/stars/fontnelle/dudu?style=flat-square" alt="Estrellas"></a>
  <a href="https://github.com/fontnelle/dudu/releases"><img src="https://img.shields.io/github/v/release/fontnelle/dudu?filter=win-v*&label=version&style=flat-square" alt="Versión"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="Licencia"></a>
  <a href="https://github.com/fontnelle/dudu/actions/workflows/ci.yml?query=branch%3Awindows"><img src="https://img.shields.io/github/actions/workflow/status/fontnelle/dudu/ci.yml?branch=windows&label=tests&style=flat-square" alt="Pruebas"></a>
  <a href="#primeros-pasos"><img src="https://img.shields.io/badge/platform-Windows-lightgrey?style=flat-square" alt="Plataforma"></a>
</div>

dudu está escrito en bash, así que en Windows corre en **Git Bash** (parte de Git para Windows, que la mayoría de las máquinas de desarrollo ya tiene). El instalador lo configura si falta, y después `dudu` funciona igual desde PowerShell, cmd y Git Bash.

## Funciones

- **Todo lo que instalaste**: paquetes de winget, scoop y Chocolatey, versiones de Node (nvm-windows, fnm, volta), paquetes globales de npm/pnpm/yarn/bun, pipx/uv, gems, cargo, herramientas de go, extensiones de VS Code y Cursor
- **Tu terminal, como estaba**: configuración de Windows Terminal, perfiles de PowerShell, Git Bash (`.bashrc`, `.minttyrc`), Starship, Neovim, WezTerm, Alacritty, Nerd Fonts, configuración de git y SSH
- **Guardado donde ya estás**: una carpeta local, Google Drive e iCloud para Windows, varios a la vez
- **Pasa de un sistema a otro**: el respaldo de una Mac se restaura aquí (Homebrew pasa a ser winget y scoop), y un respaldo de Windows se restaura en una Mac o en Linux
- **Los secretos se quedan en casa**: los tokens de tus dotfiles se enmascaran, los archivos de claves nunca se copian y `dudu secrets` saca las claves de tu `.bashrc`
- **Cifrado si quieres**: AES-256 con una contraseña guardada en el Administrador de credenciales de Windows
- **Restaurar sin miedo**: un respaldo se trata como no confiable, se revisa contra sus checksums y nunca sobrescribe un archivo sin guardar una copia
- **Funciona solo**: un respaldo diario con `dudu schedule on`, mediante el Programador de tareas
- **Habla tu idioma**: English, Português (Brasil) y Español, según tu sistema
- **Bash puro, sin otras dependencias**: Git para Windows trae todo lo que dudu usa (bash, curl, openssl, tar)

## Primeros pasos

**Instalar desde PowerShell**

```powershell
irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
```

Instala Git para Windows con winget si falta Git Bash, instala dudu y agrega `dudu` a tu PATH para PowerShell y cmd. Después abre una terminal nueva.

**O desde Git Bash**

```bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/windows/install.sh | bash
```

Los dos revisan la versión contra su `SHA256SUMS`. Para una versión: `$env:DUDU_VERSION = "0.1.0"` antes de `install.ps1`, o `| bash -s -- 0.1.0`.

**Usar**

```bash
dudu                 # menú interactivo
dudu backup          # guarda todo en tus destinos
dudu restore         # en la máquina nueva: reinstala todo
dudu status          # qué cambió desde el último respaldo
dudu outdated        # actualizaciones de winget, scoop, npm, pip, gems... y luego actualizar todo o elegir
dudu secrets         # claves encontradas en tus archivos de configuración, y moverlas a ~/.secrets
dudu schedule on     # un respaldo todos los días (12:30, o: dudu schedule on 08:00)
dudu config          # destinos, idioma, cifrado, programación
```

Todos los comandos aceptan `--dry-run` y `--only brew,node,...`. `restore` también acepta `--from <máquina>` (un respaldo de otra computadora), `--file <carpeta>` (un respaldo copiado a mano) y `--yes`. `--debug` registra cada paso en `~/.cache/dudu/dudu.log`.

## Máquina nueva, paso a paso

```powershell
irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
dudu config                       # el mismo destino de la máquina anterior
dudu restore --dry-run            # mira qué va a pasar
dudu restore
```

La restauración sigue un orden: primero los paquetes de winget, scoop y Chocolatey, luego la configuración del shell y de git, las versiones de Node, los paquetes globales y los editores. Cada paso es idempotente: lo que ya está instalado se omite, y un archivo distinto se guarda como `<archivo>.dudu-bak`. Las instalaciones de Chocolatey necesitan una terminal abierta como administrador; winget pide el permiso por su cuenta cuando un instalador lo necesita.

## De Mac a Windows

Un respaldo hecho en Mac también se restaura en Windows, hasta donde Windows lo permite. El puente es Google Drive: las dos máquinas acceden a él con `rclone`, configurado con `dudu config gdrive`.

```bash
# En la Mac: conecta Google Drive y haz el respaldo
dudu config gdrive
dudu backup

# En Windows
dudu config gdrive              # 1: la misma cuenta de Google, lista la Mac
dudu restore --dry-run --from <nombre de la mac>
dudu restore --from <nombre de la mac>
```

- **Homebrew pasa a ser paquetes de winget.** Las fórmulas y casks que tienen paquete en winget se instalan con él (`git` pasa a ser `Git.Git`, `visual-studio-code` pasa a ser `Microsoft.VisualStudioCode`...). Con scoop instalado, lo que no tiene paquete en winget se intenta con scoop con el mismo nombre. Las herramientas GNU que Git Bash ya trae (coreutils, grep, sed...) se omiten.
- **Los runtimes usan sus instaladores de Windows.** nvm pasa a ser nvm-windows si está instalado, o fnm si no; rustup y bun vienen de winget.
- **La configuración va a las rutas de Windows.** La de VS Code y Cursor pasa de `~/Library/Application Support` a `AppData\Roaming`.
- **Antes de instalar nada, el plan muestra lo que queda fuera:** apps de la Mac App Store, casks sin versión para Windows, preferencias de macOS, perfiles de Terminal.app/iTerm2 y todo lo demás bajo `~/Library`.

Un respaldo hecho en Windows se restaura en una Mac o en Linux de la misma forma: la configuración de los editores va a su lugar allá, y winget, scoop y Windows Terminal aparecen como lo que queda fuera. Los nombres que cambian están en [`lib/data/brew-windows.map`](lib/data/brew-windows.map). Para agregar una app que falta, basta una línea.

## Dónde quedan los respaldos

| Destino | Dónde | Notas |
| --- | --- | --- |
| Carpeta local | `~/dudu-backups` o cualquier carpeta | Predeterminado |
| Google Drive | `Mi unidad/dudu-<máquina>` | `dudu config gdrive`, en 4 pasos (ver abajo). Drive para escritorio se usa si está instalado (`G:\My Drive`, o su carpeta duplicada). Otra carpeta sincronizada: `dudu config set gdrive_path <carpeta>` |
| iCloud Drive | `iCloudDrive\dudu` | Con iCloud para Windows |

Apple Notes, un destino en macOS, no existe en Windows.

**`dudu config gdrive`** guarda directo en Google Drive, sin Drive para escritorio:

1. **rclone**: lo instala si falta (con winget, scoop o Chocolatey).
2. **Carpeta**: elige **1, conectar mi cuenta de Google**, y dudu crea `dudu-<máquina>` en Mi unidad. Así solo ve los archivos que él mismo crea (acceso `drive.file`), nada más de tu Drive. O elige **2, pegar el enlace de una carpeta** que ya tienes (en Drive: clic derecho › Compartir › Copiar enlace). Un enlace equivocado dice por qué: es un archivo y no una carpeta, es otro sitio, es un acortador. Una carpeta pegada necesita acceso a todo el Drive, y cada máquina tiene su `dudu-<máquina>` dentro de ella.
3. **Cuenta de Google**: se abre un navegador para iniciar sesión una vez. dudu usa un remote propio de rclone (`dudu-gdrive`), así que tus otros remotes no se tocan.
4. **Verificaciones**: se escribe un archivo de prueba, se lee de vuelta y se borra. La configuración de rclone, donde está el token de Google, queda en tu `AppData`, legible solo para ti. Si el cifrado está apagado, dudu ofrece encenderlo. También lista las máquinas que ya tienen respaldo ahí.

Al final, y después de cada respaldo, dudu muestra el enlace de la carpeta para abrirla en el navegador. Si un paso falla, no se guarda nada y la configuración anterior sigue vigente. Si la Mac guarda con Drive para escritorio: en Windows, elige 2 y pega el enlace de su carpeta `dudu`. Como no la creó dudu, no se ve con `drive.file`.

Elige **uno o más** con `dudu config` o `dudu config set destination local,gdrive`. Cada respaldo va a todos, y si uno falla los demás siguen. `restore` y `status` leen el respaldo más reciente que encuentren entre ellos. Las carpetas conservan los últimos 5 respaldos por máquina (`dudu config set keep 10`).

## Qué se respalda

| Recolector | Guarda | Restaura con |
| --- | --- | --- |
| `winget` | los ids de los paquetes que winget conoce (`winget export`) | `winget install` de cada uno que falte |
| `scoop` | buckets y apps (`scoop export`) | `scoop bucket add`, `scoop install` |
| `choco` | paquetes de Chocolatey | `choco install` (en una terminal de administrador) |
| `brew` | el Brewfile de una Mac o de Linux, al restaurar su respaldo aquí | paquetes de winget y scoop (ver arriba) |
| `shell` | `.bashrc`, `.bash_profile`, `.minttyrc`, perfiles de PowerShell, `starship.toml`, vim, Neovim (`AppData\Local\nvim`) | copia los archivos |
| `git` | `.gitconfig`, gitignore global, `~/.ssh/config`, configuración de gh | copia los archivos |
| `terminal` | Windows Terminal (`settings.json`), WezTerm, Alacritty, la lista de Nerd Fonts | copia los archivos |
| `node` | versiones de nvm-windows (o nvm, fnm, volta) y la predeterminada | `nvm install`, o fnm si no está nvm-windows |
| `npm` `pnpm` `yarn` `bun` | paquetes globales, `.npmrc` | `npm install -g` ... |
| `python` | versiones de pyenv, herramientas de pipx y uv, `pip --user` | `pipx install`, `uv tool install`, `pip install --user` |
| `ruby` `cargo` `go` | gems, crates de `cargo install`, herramientas de `go install` | las mismas herramientas (rustup y bun desde winget) |
| `vscode` `cursor` | extensiones, configuración, atajos, snippets | `code --install-extension` |

Omite recolectores con `dudu config set exclude choco,ruby`, o deja solo algunos con `dudu config set include brew,node,shell`.

## Seguridad

**Los secretos se quedan en tu máquina**

- Los valores que parecen secretos (`TOKEN=`, `_authToken=`, `password:`, `api_key`, `Bearer …`, `https://user:pass@`, `ghp_…`, `sk-…`, `npm_…`, `AKIA…`, JWTs, bloques de clave privada) se vuelven `<redacted-by-dudu>` en el respaldo. Las referencias como `$MI_VAR` se conservan.
- Los archivos de claves nunca se copian: `~/.ssh/id_*`, `~/.gnupg`, `~/.aws/credentials`, `~/.netrc`, `~/.kube/config`, `~/.docker/config.json`, tokens de `gh`, `~/.secrets`. dudu lista los que encontró para que los muevas tú mismo.
- Un archivo que dudu no puede revisar en busca de secretos queda fuera del respaldo, nunca se copia tal cual.
- Cada respaldo termina con las claves que enmascaró: archivo, línea y nombre, nunca el valor. `dudu secrets` ofrece mover las líneas `export NOMBRE=…` de tus archivos de shell a `~/.secrets`, que tu `.bashrc` luego carga desde el mismo lugar.
- Al restaurar, un archivo cuya única diferencia es el secreto enmascarado se deja como está, así que restaurar en la misma máquina nunca borra tus tokens.

**Cifrado**

`dudu config set encrypt on` pide una contraseña (12+ caracteres) y la guarda en el Administrador de credenciales de Windows (o, si eso falla, en `~/.config/dudu/key`). Desde ahí cada respaldo se vuelve un `backup.enc` (AES-256-CBC, PBKDF2 con 200.000 rondas, vía `openssl`) más un MAC que se revisa antes de descifrar cualquier cosa. Solo `manifest.json` (nombre de la máquina, fecha, qué herramientas) y un `RESTORE.md` genérico quedan legibles. En una máquina nueva, `dudu restore` pide la contraseña. **Sin ella el respaldo no se puede restaurar**, así que guárdala en tu gestor de contraseñas.

**Lo que un respaldo puede y no puede hacerte**

Cualquiera con acceso a la cuenta de Google Drive o iCloud puede cambiar una carpeta de respaldo ahí, así que dudu la trata como no confiable al restaurar:

- los nombres de paquetes se revisan (sin opciones, URLs ni rutas) antes de llegar a `winget`, `scoop`, `npm`, `pip`...;
- un Brewfile conserva solo las líneas `tap`/`brew`/`cask`/`mas`/`vscode`, así que no puede ejecutar Ruby;
- los archivos vuelven solo a las rutas que cada herramienta respalda, nunca a `~/.ssh/authorized_keys`, la carpeta Inicio o `~/.secrets`, y nunca a través de un enlace simbólico;
- cada archivo sobrescrito se guarda como `.dudu-bak`.

Con el cifrado activado, la revisión del MAC va primero: un respaldo modificado se rechaza antes de que se ejecute cualquier cosa.

## Confiabilidad

- Cada respaldo lleva un `SHA256SUMS`. Lo guardado va a una carpeta `.partial`, se revisa y luego se renombra, así que un guardado interrumpido nunca se vuelve el respaldo que usa restore.
- `restore` y `status` revisan los checksums y vuelven al respaldo anterior cuando el más reciente está dañado.
- Una herramienta que falla o tarda demasiado conserva su copia del último respaldo bueno, y el respaldo lo dice en vez de "completo".
- `keep` nunca es menor que 1, y la limpieza nunca borra el respaldo completo más reciente ni el que se acaba de guardar.
- Dos máquinas con el mismo nombre respaldan en carpetas separadas, distinguidas por un id de hardware con hash.
- Solo corre un dudu a la vez. Ctrl-C detiene el paso en curso y todo lo que inició, y borra los archivos temporales.

**Códigos de salida**

| Código | Significado |
| --- | --- |
| 0 | Todo funcionó |
| 1 | Error: no se guardó ni restauró nada |
| 2 | Hecho en parte: un destino falló, una herramienta no se pudo leer o un paso de restore falló |
| 3 | Solo `status`: esta máquina cambió desde el último respaldo |
| 130 | Interrumpido (Ctrl-C) |

## Respaldos programados

`dudu schedule on [HH:MM]` agrega un respaldo diario: una tarea del Programador de tareas llamada `dudu backup`, que corre mientras tienes la sesión iniciada, sin abrir ninguna ventana. Usa la contraseña de respaldo guardada, y una falla muestra una notificación de Windows. `dudu schedule status` lo muestra, `dudu schedule off` lo quita.

## Idioma

dudu habla English, Português (Brasil) y Español. Sigue el idioma de visualización de Windows (Configuración › Hora e idioma) sin que tengas que configurar nada, y el primer uso avisa cuál eligió.

```bash
dudu config set language es      # en, pt-BR, es, o auto para volver a seguir el sistema
DUDU_LANG=en dudu status         # un comando en otro idioma
```

O desde el menú: **Configuración › Idioma**. El `RESTORE.md` de un respaldo se escribe en el idioma de la máquina que lo hizo.

## Autocompletado

```bash
echo 'eval "$(dudu completion bash)"' >> ~/.bashrc              # Git Bash
```

## Agregar un recolector

Cada herramienta es un archivo en `lib/collectors/<nombre>.sh`:

```bash
foo_detect()   { has foo; }                                   # ¿está en esta máquina?
foo_backup()   { foo list > "$1/list.txt" || return 1; summary "$1" "$(tn "%d thing" "%d things" "$n")"; }
foo_restore()  { act foo install ...; }                        # act ejecuta, o solo muestra en --dry-run
foo_outdated() { foo outdated; }                              # opcional: "nombre actual última" por línea
foo_upgrade()  { foo upgrade "$1"; }                          # opcional: actualiza un paquete
```

Luego agrega el nombre a `DUDU_COLLECTORS` en `lib/core/common.sh` (el orden es el de la restauración). Una función de respaldo devuelve distinto de cero cuando su herramienta falla, así dudu conserva la última copia buena. Pasa las listas de paquetes por `missing_pkgs` y los archivos de configuración por `save_file` y `restore_home <dir> <rutas permitidas>`: validan nombres, enmascaran secretos y guardan copias `.dudu-bak`.

## Desarrollo

```bash
make check     # shellcheck + bats + catálogos de traducción
make install   # enlaza este checkout como ~/.local/bin/dudu
```

Esta rama es la edición para Windows. Todo lo específico de Windows queda detrás de `is_windows` (`lib/core/platform.sh`), así que `main` se fusiona sin conflictos, y el código sigue corriendo en macOS (bash 3.2) y Linux. Las pruebas simulan Windows con `fake_windows` (`tests/helpers.bash`), así que `make check` corre en cualquier lugar. El CI las corre en Git Bash en Windows, y en macOS, bash 3.2, Ubuntu, Fedora y Arch. Las versiones se etiquetan `win-vX.Y.Z`, con notas en [`CHANGELOG.windows.md`](CHANGELOG.windows.md).

## Licencia

MIT.
