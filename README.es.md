<div align="center">
  <h1>dudu</h1>
  <p><b>Respalda todo tu entorno de desarrollo con un comando y recupéralo en una máquina nueva con otro. Paquetes, runtimes, dotfiles y terminal, en macOS y Linux.</b></p>
  <p><a href="README.md">English</a> · <a href="README.pt-BR.md">Português</a> · Español</p>
  <a href="https://github.com/fontnelle/dudu/stargazers"><img src="https://img.shields.io/github/stars/fontnelle/dudu?style=flat-square" alt="Estrellas"></a>
  <a href="https://github.com/fontnelle/dudu/releases"><img src="https://img.shields.io/github/v/release/fontnelle/dudu?label=version&style=flat-square" alt="Versión"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="Licencia"></a>
  <a href="https://github.com/fontnelle/dudu/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/fontnelle/dudu/ci.yml?branch=main&label=tests&style=flat-square" alt="Pruebas"></a>
  <a href="#primeros-pasos"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square" alt="Plataforma"></a>
</div>

<p align="center">
  <img src="./docs/img/backup.svg" alt="dudu backup: 9 herramientas recolectadas, cifradas y guardadas en una carpeta local, iCloud Drive y Apple Notes" width="790" />
</p>

## Funciones

- **Todo lo que instalaste desde la terminal**: Homebrew, apt/dnf/pacman, versiones de Node, paquetes globales de npm/pnpm/yarn/bun, pyenv/pipx/uv, gems, cargo, herramientas de go, extensiones de VS Code y Cursor
- **Tu terminal, como estaba**: zsh, Oh My Zsh y plugins, Powerlevel10k/Starship, perfiles de Terminal.app e iTerm2, Ghostty, Kitty, WezTerm, Nerd Fonts, configuración de git y SSH
- **Guardado donde ya estás**: una carpeta local, iCloud Drive, Google Drive y Apple Notes, varios a la vez
- **Los secretos se quedan en casa**: los tokens de tus dotfiles se enmascaran, los archivos de claves nunca se copian y `dudu secrets` saca las claves de tu `.zshrc`
- **Cifrado si quieres**: AES-256 con una contraseña guardada en tu Llavero
- **Restaurar sin miedo**: un respaldo se trata como no confiable, se revisa contra sus checksums y nunca sobrescribe un archivo sin guardar una copia
- **Funciona solo**: un respaldo diario con `dudu schedule on`
- **Habla tu idioma**: English, Português (Brasil) y Español, según tu sistema
- **Bash puro, sin dependencias**: funciona con el bash 3.2 que viene con macOS

## Primeros pasos

**Instalar con Homebrew**

```bash
brew install fontnelle/tap/dudu
```

**O con el script**

```bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash
```

El script revisa la versión contra su `SHA256SUMS`. Opciones: `| bash -s -- 0.1.0` para una versión, `| bash -s -- --prefix ~/.local/bin` para dónde va el comando.

**Usar**

```bash
dudu                 # menú interactivo
dudu backup          # guarda todo en tus destinos
dudu restore         # en la máquina nueva: reinstala todo
dudu status          # qué cambió desde el último respaldo
dudu outdated        # actualizaciones de brew, npm, pip, gems, Node LTS... y luego actualizar todo o elegir
dudu secrets         # claves encontradas en tus archivos de configuración, y moverlas a ~/.secrets
dudu schedule on     # un respaldo todos los días (12:30, o: dudu schedule on 08:00)
dudu config          # destinos, idioma, cifrado, programación
```

Todos los comandos aceptan `--dry-run` y `--only brew,node,...`. `restore` también acepta `--from <máquina>` (un respaldo de otra computadora), `--file <carpeta>` (un respaldo copiado a mano) y `--yes`. `--debug` registra cada paso en `~/.cache/dudu/dudu.log` (necesita bash 4.1+).

## Máquina nueva, paso a paso

```bash
brew install fontnelle/tap/dudu   # o el script, en una Mac que aún no tiene Homebrew
dudu config                       # el mismo destino de la máquina anterior
dudu restore --dry-run            # mira qué va a pasar
dudu restore
```

La restauración sigue un orden: primero Homebrew (que trae pyenv, go, fuentes...), luego la configuración del shell y de git, las versiones de Node, los paquetes globales, los editores y las preferencias de macOS. Cada paso es idempotente: lo que ya está instalado se omite, y un archivo distinto se guarda como `<archivo>.dudu-bak`.

## De Mac a Linux

Un respaldo hecho en Mac también se restaura en Linux, hasta donde Linux lo permite. El puente es Google Drive: las dos máquinas acceden a él con `rclone`, configurado con `dudu config gdrive`.

```bash
# En la Mac: conecta Google Drive y haz el respaldo
dudu config gdrive
dudu backup

# En Linux
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash
dudu config gdrive              # Enter: la misma carpeta dudu en la que escribe la Mac
dudu restore --dry-run --from <nombre de la mac>
dudu restore --from <nombre de la mac>
```

- **Homebrew pasa a ser paquetes del sistema.** Las fórmulas se instalan con apt, dnf o pacman con el mismo nombre, cuando el repositorio tiene el paquete (`fd` pasa a ser `fd-find`, `node` pasa a ser `nodejs`...). Los casks conocidos vienen del sistema o de Flathub (VS Code, Chrome, Slack, Spotify, Obsidian...). Homebrew en sí no se instala. Si ya está en la máquina, las fórmulas sin paquete nativo se instalan con él.
- **La configuración va a las rutas de Linux.** La de VS Code y Cursor pasa de `~/Library/Application Support` a `~/.config`, y la de Ghostty también.
- **Antes de instalar nada, el plan muestra lo que queda fuera:** apps de la Mac App Store, casks sin versión para Linux, preferencias de macOS y perfiles de Terminal.app/iTerm2.

Los nombres que cambian están en [`lib/data/brew-linux.map`](lib/data/brew-linux.map). Para agregar una app que falta, basta una línea.

## Dónde quedan los respaldos

| Destino | Dónde | Notas |
| --- | --- | --- |
| Carpeta local | `~/dudu-backups` o cualquier carpeta | Predeterminado |
| iCloud Drive | `iCloud Drive/dudu` | macOS |
| Google Drive | `Mi unidad/dudu` | `dudu config gdrive`, en macOS y Linux, en 4 pasos (ver abajo). Drive para escritorio se usa si está instalado. Carpeta sincronizada: `dudu config set gdrive_path <carpeta>` |
| Apple Notes | la nota `dudu backup - <máquina>` en la carpeta `dudu` | macOS. Un resumen legible más todo el respaldo incrustado. El primer guardado pide permiso para controlar Notas |

**`dudu config gdrive`** guarda directo en Google Drive, sin Drive para escritorio:

1. **rclone**: lo instala si falta (`brew install rclone`, o apt/dnf/pacman).
2. **Carpeta**: Enter crea una carpeta `dudu` en Mi unidad. Así dudu solo ve los archivos que él mismo crea (acceso `drive.file`), nada más de tu Drive. O pega el enlace de una carpeta (`https://drive.google.com/drive/folders/…`). Cualquier otro enlace se rechaza, incluidos acortadores y sitios parecidos. Una carpeta pegada necesita acceso a todo el Drive.
3. **Cuenta de Google**: se abre un navegador para iniciar sesión una vez. dudu usa un remote propio de rclone (`dudu-gdrive`), así que tus otros remotes no se tocan.
4. **Verificaciones**: se escribe un archivo de prueba, se lee de vuelta y se borra. La configuración de rclone, donde está el token de Google, queda legible solo para ti. Si el cifrado está apagado, dudu ofrece encenderlo. También lista las máquinas que ya tienen respaldo ahí.

Si un paso falla, no se guarda nada y la configuración anterior sigue vigente. Si la Mac guarda con Drive para escritorio: en Linux, pega el enlace de su carpeta `dudu`. Como no la creó dudu, no se ve con `drive.file`.

Elige **uno o más** con `dudu config` o `dudu config set destination icloud,notes`. Cada respaldo va a todos, y si uno falla los demás siguen. `restore` y `status` leen el respaldo más reciente que encuentren entre ellos. Las carpetas conservan los últimos 5 respaldos por máquina (`dudu config set keep 10`).

## Qué se respalda

| Recolector | Guarda | Restaura con |
| --- | --- | --- |
| `brew` | Brewfile (fórmulas, casks, taps, Mac App Store) | `brew bundle install` (instala Homebrew si hace falta). En Linux, el Brewfile de una Mac pasa a ser paquetes apt/dnf/pacman y Flathub |
| `syspkgs` | paquetes apt/dnf/pacman instalados a mano, flatpak, snap | el gestor de paquetes del sistema |
| `shell` | `.zshrc`, `.zprofile`, `.bashrc`, `.p10k.zsh`, `starship.toml`, tmux, vim, fish, nvim, plugins/temas propios de Oh My Zsh (como URLs de git) | copia los archivos, instala Oh My Zsh, clona los plugins |
| `git` | `.gitconfig`, gitignore global, `~/.ssh/config`, configuración de gh | copia los archivos |
| `terminal` | perfiles de Terminal.app e iTerm2, Ghostty, Alacritty, Kitty, WezTerm, la lista de Nerd Fonts | `defaults import`, copia los archivos |
| `node` | versiones de nvm (o fnm/volta) y la predeterminada | instala nvm, `nvm install` de cada versión |
| `npm` `pnpm` `yarn` `bun` | paquetes globales (por versión de Node con nvm), `.npmrc` | `npm install -g` ... |
| `python` | versiones de pyenv, herramientas de pipx y uv, `pip --user` | `pyenv install`, `pipx install`, `uv tool install` |
| `ruby` `cargo` `go` | gems/rbenv, crates de `cargo install`, herramientas de `go install` | las mismas herramientas |
| `vscode` `cursor` | extensiones, configuración, atajos, snippets | `code --install-extension` |
| `macos` | una selección de preferencias del Dock, Finder, teclado y capturas de pantalla | `defaults write` |

Omite recolectores con `dudu config set exclude macos,ruby`, o deja solo algunos con `dudu config set include brew,node,shell`.

## Seguridad

**Los secretos se quedan en tu máquina**

- Los valores que parecen secretos (`TOKEN=`, `_authToken=`, `password:`, `api_key`, `Bearer …`, `https://user:pass@`, `ghp_…`, `sk-…`, `npm_…`, `AKIA…`, JWTs, bloques de clave privada) se vuelven `<redacted-by-dudu>` en el respaldo. Las referencias como `$(security …)` o `$MI_VAR` se conservan.
- Los archivos de claves nunca se copian: `~/.ssh/id_*`, `~/.gnupg`, `~/.aws/credentials`, `~/.netrc`, `~/.kube/config`, `~/.docker/config.json`, tokens de `gh`, `~/.secrets`. dudu lista los que encontró para que los muevas tú mismo.
- Un archivo que dudu no puede revisar en busca de secretos queda fuera del respaldo, nunca se copia tal cual.
- Cada respaldo termina con las claves que enmascaró: archivo, línea y nombre, nunca el valor. `dudu secrets` ofrece mover las líneas `export NOMBRE=…` de tus archivos de shell a `~/.secrets` (modo 600), que tu `.zshrc` luego carga desde el mismo lugar.
- Al restaurar, un archivo cuya única diferencia es el secreto enmascarado se deja como está, así que restaurar en la misma máquina nunca borra tus tokens.

**Cifrado**

`dudu config set encrypt on` pide una contraseña (12+ caracteres) y la guarda en el Llavero de macOS (en Linux, `secret-tool` o `~/.config/dudu/key` con modo 600). Desde ahí cada respaldo se vuelve un `backup.enc` (AES-256-CBC, PBKDF2 con 200.000 rondas, vía `openssl`) más un MAC que se revisa antes de descifrar cualquier cosa. Solo `manifest.json` (nombre de la máquina, fecha, qué herramientas) y un `RESTORE.md` genérico quedan legibles. En una máquina nueva, `dudu restore` pide la contraseña. **Sin ella el respaldo no se puede restaurar**, así que guárdala en tu gestor de contraseñas.

**Lo que un respaldo puede y no puede hacerte**

Cualquiera con acceso a la cuenta de iCloud o Google Drive puede cambiar una carpeta de respaldo ahí, así que dudu la trata como no confiable al restaurar:

- los nombres de paquetes se revisan (sin opciones, URLs ni rutas) antes de llegar a `apt`, `brew`, `npm`, `pip`...;
- un Brewfile conserva solo las líneas `tap`/`brew`/`cask`/`mas`/`vscode`, así que no puede ejecutar Ruby;
- los archivos vuelven solo a las rutas que cada herramienta respalda, nunca a `~/.ssh/authorized_keys`, `~/Library/LaunchAgents` o `~/.secrets`, y nunca a través de un enlace simbólico;
- las preferencias de macOS se limitan a una lista conocida, y cada archivo sobrescrito se guarda como `.dudu-bak`.

Con el cifrado activado, la revisión del MAC va primero: un respaldo modificado se rechaza antes de que se ejecute cualquier cosa.

## Confiabilidad

- Cada respaldo lleva un `SHA256SUMS`. Lo guardado va a una carpeta `.partial`, se revisa y luego se renombra, así que un guardado interrumpido nunca se vuelve el respaldo que usa restore. Las notas se leen de vuelta y se revisan, y la nota anterior se conserva como "(previous)".
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

`dudu schedule on [HH:MM]` agrega un respaldo diario: un LaunchAgent en macOS, un timer de usuario de systemd en Linux. Corre sin terminal, así que usa la contraseña de respaldo guardada, y una falla muestra una notificación. Si usas Apple Notes, haz primero un respaldo a mano para que macOS pueda pedir el permiso. `dudu schedule status` lo muestra, `dudu schedule off` lo quita.

## Idioma

dudu habla English, Português (Brasil) y Español. Sigue el idioma de tu sistema (`LANG`, o Configuración del Sistema en macOS) sin que tengas que configurar nada, y el primer uso avisa cuál eligió.

```bash
dudu config set language es      # en, pt-BR, es, o auto para volver a seguir el sistema
DUDU_LANG=en dudu status         # un comando en otro idioma
```

O desde el menú: **Configuración › Idioma**. El `RESTORE.md` de un respaldo (y su nota en Apple Notes) se escribe en el idioma de la máquina que lo hizo. Las descripciones del autocompletado de zsh siguen el mismo ajuste.

## Autocompletado y resaltado en el shell

```bash
dudu completion zsh > "${fpath[1]}/_dudu"                       # autocompletado con tab en zsh
echo 'eval "$(dudu completion bash)"' >> ~/.bashrc              # autocompletado con tab en bash
echo "source $(dudu completion highlight --path)" >> ~/.zshrc   # resaltado en zsh
```

Homebrew instala el autocompletado por ti. Con [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) o [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting), `dudu backup` muestra el subcomando en amarillo mientras escribes, y un error como `dudu bakcup` en rojo.

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

El código debe correr en bash 3.2 (el de macOS): sin arrays asociativos, sin `mapfile`, sin `${var,,}`, y `${VAR}` antes de cualquier carácter no ASCII. Los mensajes se escriben en inglés como `t "text %s" "$value"` (o `tn` para plurales) y se traducen en `lib/i18n/pt-BR.sh` y `lib/i18n/es.sh`; `make check` falla cuando falta un mensaje en un catálogo. El CI corre las pruebas en macOS, bash 3.2, Ubuntu, Fedora y Arch.

## Licencia

MIT.
