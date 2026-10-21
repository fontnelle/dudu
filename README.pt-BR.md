<div align="center">
  <h1>dudu para Windows</h1>
  <p><b>Faça backup de todo o seu ambiente de desenvolvimento com um comando e devolva tudo numa máquina nova com outro. Pacotes, runtimes, dotfiles e terminal, no Windows.</b></p>
  <p><a href="README.md">English</a> · Português · <a href="README.es.md">Español</a></p>
  <p>Está no macOS ou no Linux? Use a <a href="https://github.com/fontnelle/dudu/tree/main">branch <code>main</code></a>.</p>
  <a href="https://github.com/fontnelle/dudu/stargazers"><img src="https://img.shields.io/github/stars/fontnelle/dudu?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/fontnelle/dudu/releases"><img src="https://img.shields.io/github/v/release/fontnelle/dudu?filter=win-v*&label=version&style=flat-square" alt="Versão"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="Licença"></a>
  <a href="https://github.com/fontnelle/dudu/actions/workflows/ci.yml?query=branch%3Awindows"><img src="https://img.shields.io/github/actions/workflow/status/fontnelle/dudu/ci.yml?branch=windows&label=tests&style=flat-square" alt="Testes"></a>
  <a href="#começando"><img src="https://img.shields.io/badge/platform-Windows-lightgrey?style=flat-square" alt="Plataforma"></a>
</div>

O dudu é escrito em bash, então no Windows ele roda no **Git Bash** (que vem com o Git for Windows, já presente na maioria das máquinas de dev). O instalador configura o Git Bash se ele faltar, e o `dudu` passa a funcionar tanto no PowerShell quanto no cmd e no Git Bash.

## Recursos

- **Tudo que você instalou**: pacotes do winget, do scoop e do Chocolatey, versões do Node (nvm-windows, fnm, volta), pacotes globais do npm/pnpm/yarn/bun, pipx/uv, gems, cargo, ferramentas do go, extensões do VS Code e do Cursor
- **Seu terminal, do jeito que estava**: configurações do Windows Terminal, perfis do PowerShell, Git Bash (`.bashrc`, `.minttyrc`), Starship, Neovim, WezTerm, Alacritty, Nerd Fonts, config do git e do SSH
- **Salvo onde você já está**: pasta local, Google Drive e iCloud para Windows, vários ao mesmo tempo
- **Muda de sistema**: o backup de um Mac restaura aqui (o Homebrew vira winget e scoop), e um backup do Windows restaura num Mac ou no Linux
- **Segredos ficam em casa**: tokens nos dotfiles são mascarados, arquivos de chave nunca são copiados, e o `dudu secrets` tira as chaves do seu `.bashrc`
- **Criptografado, se você quiser**: AES-256 com uma senha guardada no Gerenciador de Credenciais do Windows
- **Restore seguro**: o backup é tratado como não confiável, conferido pelos checksums, e nenhum arquivo é sobrescrito sem ficar uma cópia
- **Roda sozinho**: um backup por dia com `dudu schedule on`, pelo Agendador de Tarefas
- **Fala a sua língua**: English, Português (Brasil) e Español, pelo idioma do sistema
- **Bash puro, sem outras dependências**: o Git for Windows traz tudo que o dudu usa (bash, curl, openssl, tar)

## Começando

**Instale pelo PowerShell**

```powershell
irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
```

Ele instala o Git for Windows com o winget se faltar o Git Bash, instala o dudu e coloca o `dudu` no PATH do PowerShell e do cmd. Depois, abra um terminal novo.

**Ou pelo Git Bash**

```bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/windows/install.sh | bash
```

Os dois conferem o release pelo `SHA256SUMS`. Para uma versão específica: `$env:DUDU_VERSION = "0.1.0"` antes do `install.ps1`, ou `| bash -s -- 0.1.0`.

**Use**

```bash
dudu                 # menu interativo
dudu backup          # salva tudo nos seus destinos
dudu restore         # na máquina nova: reinstala tudo
dudu status          # o que mudou desde o último backup
dudu outdated        # atualizações do winget, scoop, npm, pip, gems... e atualiza tudo ou escolhe
dudu secrets         # chaves nos seus arquivos de config, e como movê-las para ~/.secrets
dudu schedule on     # um backup por dia (12:30, ou: dudu schedule on 08:00)
dudu config          # destinos, idioma, criptografia, agendamento
```

Todos os comandos aceitam `--dry-run` e `--only brew,node,...`. O `restore` também aceita `--from <máquina>` (backup de outro computador), `--file <pasta>` (backup copiado à mão) e `--yes`. Com `--debug`, cada passo vai para `~/.cache/dudu/dudu.log`.

## Máquina nova, passo a passo

```powershell
irm https://raw.githubusercontent.com/fontnelle/dudu/windows/install.ps1 | iex
dudu config                       # o mesmo destino da máquina antiga
dudu restore --dry-run            # veja o que vai acontecer
dudu restore
```

O restore roda em ordem: primeiro os pacotes do winget, do scoop e do Chocolatey, depois a config do shell e do git, as versões do Node, os pacotes globais e os editores. Todo passo pode ser repetido: o que já está instalado é pulado, e um arquivo diferente fica guardado como `<arquivo>.dudu-bak`. As instalações do Chocolatey precisam de um terminal aberto como administrador; o winget pede permissão sozinho quando um instalador precisa.

## Do Mac para o Windows

Um backup feito no Mac também restaura no Windows, até onde o Windows permite. A ponte é o Google Drive: as duas máquinas acessam ele pelo `rclone`, configurado com `dudu config gdrive`.

```bash
# No Mac: conecte o Google Drive e faça o backup
dudu config gdrive
dudu backup

# No Windows
dudu config gdrive              # 1: a mesma conta Google, ele lista o Mac
dudu restore --dry-run --from <nome do mac>
dudu restore --from <nome do mac>
```

- **O Homebrew vira pacotes do winget.** Fórmulas e casks que têm pacote no winget são instalados por ele (`git` vira `Git.Git`, `visual-studio-code` vira `Microsoft.VisualStudioCode`...). Com o scoop instalado, o que não tem pacote no winget é tentado no scoop com o mesmo nome. Ferramentas GNU que o Git Bash já tem (coreutils, grep, sed...) são puladas.
- **Os runtimes usam os instaladores do Windows.** O nvm vira nvm-windows, se ele estiver instalado, ou fnm caso contrário; rustup e bun vêm do winget.
- **As configurações vão para os caminhos do Windows.** As do VS Code e do Cursor saem de `~/Library/Application Support` e vão para `AppData\Roaming`.
- **Antes de instalar qualquer coisa, o plano mostra o que fica de fora:** apps da Mac App Store, casks sem versão para Windows, preferências do macOS, perfis do Terminal.app/iTerm2 e tudo mais que está em `~/Library`.

Um backup feito no Windows restaura num Mac ou no Linux do mesmo jeito: as configurações dos editores vão para o lugar delas lá, e winget, scoop e Windows Terminal aparecem como fora do restore. Os nomes que mudam estão em [`lib/data/brew-windows.map`](lib/data/brew-windows.map). Para incluir um app que falta, basta uma linha.

## Onde os backups ficam

| Destino | Onde | Observações |
| --- | --- | --- |
| Pasta local | `~/dudu-backups` ou qualquer pasta | Padrão |
| Google Drive | `Meu Drive/dudu-<máquina>` | `dudu config gdrive`, em 4 etapas (veja abaixo). O Drive for desktop é usado se estiver instalado (`G:\Meu Drive`, ou a pasta espelhada dele). Outra pasta sincronizada: `dudu config set gdrive_path <pasta>` |
| iCloud Drive | `iCloudDrive\dudu` | Com o iCloud para Windows |

O Apple Notes, um destino no macOS, não existe no Windows.

**`dudu config gdrive`** salva direto no Google Drive, sem o Drive for desktop:

1. **rclone**: instala, se faltar (com winget, scoop ou Chocolatey).
2. **Pasta**: escolha **1, conectar minha conta Google**, e o dudu cria `dudu-<máquina>` no Meu Drive. Assim ele só enxerga os arquivos que ele mesmo cria (acesso `drive.file`), nada mais do seu Drive. Ou escolha **2, colar o link de uma pasta** que você já tem (no Drive: botão direito › Compartilhar › Copiar link). Um link errado diz o motivo: é um arquivo e não uma pasta, é outro site, é um encurtador. Uma pasta colada precisa de acesso ao Drive inteiro, e cada máquina ganha a sua `dudu-<máquina>` dentro dela.
3. **Conta Google**: um navegador abre para você entrar uma vez. O dudu usa um remote próprio do rclone (`dudu-gdrive`), então os seus outros remotes não são tocados.
4. **Verificações**: um arquivo de teste é gravado, lido de volta e apagado. A config do rclone, onde fica o token do Google, fica no seu `AppData`, que só você consegue ler. Se a criptografia estiver desligada, o dudu oferece ligar. Ele também lista as máquinas que já têm backup lá.

No fim, e depois de cada backup, o dudu mostra o link da pasta para abrir no navegador. Se uma etapa falha, nada é salvo e a configuração anterior continua valendo. Se o Mac salva pelo Drive for desktop: no Windows, escolha 2 e cole o link da pasta `dudu` dele. Como ela não foi criada pelo dudu, não aparece com `drive.file`.

Escolha **um ou mais** com `dudu config` ou `dudu config set destination local,gdrive`. Cada backup vai para todos, e um que falhe não impede os outros. `restore` e `status` usam o backup mais novo entre eles. Nas pastas ficam os 5 últimos backups de cada máquina (`dudu config set keep 10`).

## O que entra no backup

| Collector | Salva | Restaura com |
| --- | --- | --- |
| `winget` | os ids dos pacotes que o winget conhece (`winget export`) | `winget install` de cada um que falta |
| `scoop` | buckets e apps (`scoop export`) | `scoop bucket add`, `scoop install` |
| `choco` | pacotes do Chocolatey | `choco install` (num terminal de administrador) |
| `brew` | o Brewfile de um Mac ou Linux, ao restaurar o backup deles aqui | pacotes do winget e do scoop (veja acima) |
| `shell` | `.bashrc`, `.bash_profile`, `.minttyrc`, perfis do PowerShell, `starship.toml`, vim, Neovim (`AppData\Local\nvim`) | copia os arquivos |
| `git` | `.gitconfig`, gitignore global, `~/.ssh/config`, config do gh | copia os arquivos |
| `terminal` | Windows Terminal (`settings.json`), WezTerm, Alacritty, a lista de Nerd Fonts | copia os arquivos |
| `node` | versões do nvm-windows (ou nvm, fnm, volta) e a padrão | `nvm install`, ou fnm quando não há nvm-windows |
| `npm` `pnpm` `yarn` `bun` | pacotes globais, `.npmrc` | `npm install -g` ... |
| `python` | versões do pyenv, ferramentas do pipx e do uv, `pip --user` | `pipx install`, `uv tool install`, `pip install --user` |
| `ruby` `cargo` `go` | gems, crates do `cargo install`, ferramentas do `go install` | as mesmas ferramentas (rustup e bun pelo winget) |
| `vscode` `cursor` | extensões, settings, atalhos, snippets | `code --install-extension` |

Pule collectors com `dudu config set exclude choco,ruby`, ou fique só com alguns com `dudu config set include brew,node,shell`.

## Segurança

**Segredos não saem da sua máquina**

- Valores com cara de segredo (`TOKEN=`, `_authToken=`, `password:`, `api_key`, `Bearer …`, `https://user:pass@`, `ghp_…`, `sk-…`, `npm_…`, `AKIA…`, JWTs, blocos de chave privada) viram `<redacted-by-dudu>` no backup. Referências como `$MY_VAR` são mantidas.
- Arquivos de chave nunca são copiados: `~/.ssh/id_*`, `~/.gnupg`, `~/.aws/credentials`, `~/.netrc`, `~/.kube/config`, `~/.docker/config.json`, tokens do `gh`, `~/.secrets`. O dudu lista os que encontrou para você levar por conta própria.
- Um arquivo que o dudu não consegue checar fica fora do backup, nunca é copiado como está.
- Todo backup termina listando as chaves que mascarou: arquivo, linha e nome, nunca o valor. O `dudu secrets` oferece mover as linhas `export NOME=…` dos seus arquivos de shell para `~/.secrets`, que o `.bashrc` passa a carregar no mesmo ponto.
- No restore, um arquivo cuja única diferença é o segredo mascarado não é sobrescrito, então restaurar na mesma máquina nunca apaga seus tokens.

**Criptografia**

`dudu config set encrypt on` pede uma senha (12+ caracteres) e a guarda no Gerenciador de Credenciais do Windows (ou, se isso falhar, em `~/.config/dudu/key`). Cada backup vira um `backup.enc` (AES-256-CBC, PBKDF2 com 200.000 rodadas, via `openssl`) mais um MAC, conferido antes de decifrar qualquer coisa. Só o `manifest.json` (nome da máquina, data, quais ferramentas) e um `RESTORE.md` genérico ficam legíveis. Numa máquina nova, o `dudu restore` pede a senha. **Sem ela o backup não pode ser restaurado**, então guarde-a no seu gerenciador de senhas.

**O que um backup pode e não pode fazer com você**

Quem tiver acesso à conta do Google Drive ou do iCloud pode alterar uma pasta de backup lá, então o dudu a trata como não confiável no restore:

- nomes de pacote são validados (sem opções, URLs ou caminhos) antes de chegar ao `winget`, `scoop`, `npm`, `pip`...;
- o Brewfile fica só com linhas `tap`/`brew`/`cask`/`mas`/`vscode`, então não roda Ruby;
- arquivos só voltam para os caminhos que cada ferramenta salva, nunca para `~/.ssh/authorized_keys`, a pasta Inicializar ou `~/.secrets`, e nunca através de symlink;
- todo arquivo sobrescrito fica como `.dudu-bak`.

Com a criptografia ligada, a checagem do MAC vem primeiro: um backup alterado é recusado antes de qualquer coisa rodar.

## Confiabilidade

- Todo backup leva um `SHA256SUMS`. A gravação vai para uma pasta `.partial`, é conferida e só então renomeada, então um save interrompido nunca vira o backup usado no restore.
- `restore` e `status` conferem os checksums e usam o backup anterior se o mais novo estiver danificado.
- Uma ferramenta que falha ou estoura o tempo mantém a cópia do último backup bom, e o backup avisa em vez de dizer "complete".
- `keep` nunca é menor que 1, e a limpeza nunca apaga o backup completo mais novo nem o que acabou de ser salvo.
- Duas máquinas com o mesmo nome salvam em pastas separadas, diferenciadas por um id de hardware com hash.
- Só um dudu roda por vez. Ctrl-C para o passo atual e tudo que ele iniciou, e apaga os temporários.

**Códigos de saída**

| Código | Significado |
| --- | --- |
| 0 | Tudo certo |
| 1 | Erro: nada foi salvo ou restaurado |
| 2 | Parcial: um destino falhou, uma ferramenta não pôde ser lida ou um passo do restore falhou |
| 3 | Só no `status`: a máquina mudou desde o último backup |
| 130 | Interrompido (Ctrl-C) |

## Backup agendado

`dudu schedule on [HH:MM]` cria um backup diário: uma tarefa do Agendador de Tarefas chamada `dudu backup`, que roda enquanto você está conectado, sem abrir janela. Ela usa a senha do backup que está guardada, e uma falha aparece como notificação do Windows. `dudu schedule status` mostra o agendamento e `dudu schedule off` o remove.

## Idioma

O dudu fala English, Português (Brasil) e Español. Ele segue o idioma de exibição do Windows (Configurações › Hora e idioma) sem precisar configurar nada, e o primeiro uso avisa qual idioma escolheu.

```bash
dudu config set language es      # en, pt-BR, es, ou auto para voltar a seguir o sistema
DUDU_LANG=en dudu status         # um comando em outro idioma
```

Ou pelo menu: **Configurações › Idioma**. O `RESTORE.md` de um backup sai no idioma da máquina que fez o backup.

## Autocompletar

```bash
echo 'eval "$(dudu completion bash)"' >> ~/.bashrc              # Git Bash
```

## Criando um collector

Cada ferramenta é um arquivo em `lib/collectors/<nome>.sh`:

```bash
foo_detect()   { has foo; }                                   # está nesta máquina?
foo_backup()   { foo list > "$1/list.txt" || return 1; summary "$1" "$(tn "%d thing" "%d things" "$n")"; }
foo_restore()  { act foo install ...; }                        # act executa, ou só mostra no --dry-run
foo_outdated() { foo outdated; }                              # opcional: "nome atual mais_nova" por linha
foo_upgrade()  { foo upgrade "$1"; }                          # opcional: atualiza um pacote
```

Depois inclua o nome em `DUDU_COLLECTORS` no `lib/core/common.sh` (a ordem é a ordem do restore). A função de backup retorna erro quando a ferramenta falha, para o dudu manter a última cópia boa. Passe listas de pacotes pelo `missing_pkgs` e arquivos de config pelo `save_file` e pelo `restore_home <pasta> <caminhos permitidos>`: eles validam nomes, mascaram segredos e guardam as cópias `.dudu-bak`.

## Desenvolvimento

```bash
make check     # shellcheck + bats + catálogos de tradução
make install   # liga este checkout como ~/.local/bin/dudu
```

Esta branch é a edição para Windows. Tudo que é específico do Windows fica atrás do `is_windows` (`lib/core/platform.sh`), então o `main` entra sem conflito, e o código continua rodando no macOS (bash 3.2) e no Linux. Os testes simulam o Windows com `fake_windows` (`tests/helpers.bash`), então o `make check` roda em qualquer lugar. O CI roda os testes no Git Bash no Windows, e no macOS, no bash 3.2, no Ubuntu, no Fedora e no Arch. Os releases recebem a tag `win-vX.Y.Z`, com as notas em [`CHANGELOG.windows.md`](CHANGELOG.windows.md).

## Licença

MIT.
