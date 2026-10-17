# dudu

**Seu ambiente de dev, com backup.** Um comando salva tudo o que você instalou pelo terminal: Homebrew, nvm e versões do Node, pacotes globais do npm/pnpm/yarn/bun, pyenv/pipx/uv, gems, cargo, ferramentas do go e extensões do VS Code/Cursor. Também salva a configuração do terminal: zsh, Oh My Zsh, Powerlevel10k/Starship, perfis do Terminal.app/iTerm2 e git. Numa máquina nova, outro comando põe tudo de volta.

[English](README.md)

Bash puro, sem dependências. Roda no macOS (inclusive no bash 3.2 que vem com ele) e no Linux (apt, dnf, pacman).

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash
```

## Uso

```bash
dudu                 # menu interativo
dudu backup          # salva tudo no destino escolhido
dudu restore         # na máquina nova: reinstala tudo
dudu status          # o que mudou desde o último backup
dudu outdated        # atualizações disponíveis (brew, npm, pip, gems, Node LTS...)
                     # depois: [a] atualiza tudo, [s] escolhe num checklist, [n] agora não
dudu config          # escolhe onde salvar (um ou mais destinos)
dudu secrets         # chaves nos seus arquivos de config, e como movê-las para ~/.secrets
dudu schedule on     # um backup por dia (12:30, ou: dudu schedule on 08:00)
```

Todos os comandos aceitam `--dry-run` e `--only brew,node,...`. O `restore` também aceita:
- `--from <máquina>`, para backups vindos de outro computador;
- `--file <pasta>`, para um backup copiado à mão;
- `--yes`, para não pedir confirmação.

Com `--debug`, qualquer comando registra cada passo em `~/.cache/dudu/dudu.log` (precisa de bash 4.1+).

### Códigos de saída

| Código | Significado |
| --- | --- |
| 0 | Tudo certo |
| 1 | Erro: nada foi salvo ou restaurado |
| 2 | Parcial: um destino falhou, uma ferramenta não pôde ser lida ou um passo do restore falhou |
| 3 | Só no `status`: a máquina mudou desde o último backup |
| 130 | Interrompido (Ctrl-C) |

### Backup agendado

`dudu schedule on [HH:MM]` cria um backup diário: um LaunchAgent no macOS e um timer de usuário do systemd no Linux. Ele roda sem terminal, então usa a senha do backup que está guardada, e uma falha aparece como notificação. Se você usa o Apple Notes, faça antes um backup à mão para o macOS pedir a permissão. `dudu schedule off` remove o agendamento e `dudu schedule status` mostra como está.

### Autocompletar e highlighting no terminal

```bash
dudu completion zsh > "${fpath[1]}/_dudu"                       # autocompletar no zsh
echo 'eval "$(dudu completion bash)"' >> ~/.bashrc              # autocompletar no bash
echo "source $(dudu completion highlight --path)" >> ~/.zshrc   # highlighting no zsh
```

Com o [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) ou o [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) instalado, `dudu backup` fica com o subcomando em amarelo enquanto você digita, e um erro como `dudu bakcup` fica em vermelho. Sem nenhum dos dois plugins, a linha não faz nada.

### Máquina nova, passo a passo

```bash
curl -fsSL https://raw.githubusercontent.com/fontnelle/dudu/main/install.sh | bash
dudu config              # o mesmo destino da máquina antiga (ex.: iCloud Drive)
dudu restore --dry-run   # veja o que vai acontecer
dudu restore
```

## Destinos

- **Pasta local**: `~/dudu-backups` ou qualquer pasta. É o destino padrão.
- **iCloud Drive**: `iCloud Drive/dudu`.
- **Google Drive**: no macOS, usa a pasta do Drive para desktop. No Linux, uma pasta sincronizada ou o `rclone`.
- **Notas do macOS**: cria a nota `dudu backup - <máquina>` na pasta `dudu`, com um resumo legível e o backup completo embutido. No primeiro uso o macOS pede permissão para controlar o Notas.

Dá para marcar **mais de um** destino em `dudu config`, que abre um checklist. Cada backup é salvo em todos eles, e se um falhar os outros continuam valendo. O `restore` e o `status` usam o backup mais recente que encontrarem.

## Criptografia

`dudu config set encrypt on` pede uma senha (12+ caracteres) e a guarda no Keychain do macOS (no Linux: `secret-tool`, ou `~/.config/dudu/key` com permissão 600). A partir daí, cada backup vira um `backup.enc` (AES-256-CBC, PBKDF2 com 200.000 rodadas, via `openssl`) mais um MAC, conferido antes de decifrar qualquer coisa. Só o `manifest.json` (nome da máquina, data, quais ferramentas) e um `RESTORE.md` genérico ficam legíveis. Numa máquina nova, o `dudu restore` pede a senha. **Sem ela o backup não pode ser restaurado**, então guarde-a no seu gerenciador de senhas.

## Confiabilidade

- Todo backup leva um `SHA256SUMS`. A gravação vai para uma pasta `.partial`, é conferida e só então renomeada, então um save interrompido nunca vira o backup usado no restore. No Notes, a nota é lida de volta e conferida, e a anterior fica como "(previous)".
- `restore` e `status` conferem os checksums e usam o backup anterior se o mais novo estiver danificado.
- `keep` nunca é menor que 1, e a limpeza nunca apaga o backup completo mais novo nem o que acabou de ser salvo.
- Uma ferramenta que falha ou estoura o tempo mantém a cópia do último backup bom, e o backup avisa (`⚠ Backup saved, could not read: …`).
- Duas máquinas com o mesmo nome salvam em pastas separadas (`host-ab12`), usando um id de hardware com hash.
- Só um dudu roda por vez. Ctrl-C para o passo atual e tudo que ele iniciou, e apaga os temporários.

## O que um backup pode e não pode fazer com você

Quem tiver acesso à conta do iCloud ou do Google Drive pode alterar uma pasta de backup lá. No restore, o dudu trata essa pasta como não confiável:
- nomes de pacote são validados (sem opções, URLs ou caminhos) antes de chegar ao `apt`, `brew`, `npm`, `pip`...;
- o Brewfile fica só com linhas `tap`/`brew`/`cask`/`mas`/`vscode`, então não roda Ruby;
- arquivos só voltam para os caminhos que cada ferramenta salva, nunca para `~/.ssh/authorized_keys`, `~/Library/LaunchAgents` ou `~/.secrets`, e nunca através de symlink;
- preferências do macOS se limitam a uma lista conhecida, e todo arquivo sobrescrito fica como `.dudu-bak`.

Com a criptografia ligada, entra também a checagem do MAC: um backup alterado é recusado antes de qualquer coisa rodar.

## Segredos não saem da sua máquina

- Valores com cara de segredo (`TOKEN=`, `_authToken=`, `password:`, `api_key`, `ghp_…`, `sk-…`) viram `<redacted-by-dudu>` no backup.
- Chaves nunca são copiadas: `~/.ssh/id_*`, `~/.gnupg`, `~/.aws/credentials`, `~/.netrc` e afins. O dudu lista as que encontrou para você levar por um meio seguro.
- No restore, um arquivo cuja única diferença é o segredo mascarado não é sobrescrito.
- No fim de todo backup (e no `dudu status`), o dudu avisa cada chave que mascarou: arquivo, linha e nome, nunca o valor.
- `dudu secrets` lista todas e oferece mover as linhas `export NOME=…` dos seus arquivos de shell para `~/.secrets` (permissão 600). O `.zshrc` passa a carregar esse arquivo no mesmo ponto, então o shell funciona igual. O `~/.secrets` nunca entra no backup, e a versão antiga fica em `.zshrc.dudu-bak`.

O detalhe de cada collector e como criar um novo está no [README em inglês](README.md#what-gets-backed-up).
