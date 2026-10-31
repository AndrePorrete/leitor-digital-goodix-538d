# fprint-538d — leitor de digital Goodix 27c6:538d no Linux

*[English version: README.md](README.md)*

Faz o leitor de digital Goodix `27c6:538d` (botão de ligar do Dell Inspiron 5590 e de outros
notebooks Dell) funcionar no Linux: login, desbloqueio de tela, `sudo` e janelas de senha.

| Teste guiado num Inspiron 5590 | |
|---|---|
| Dedo cadastrado | 8/8 aceitos |
| Outros dedos | 0/8 aceitos |

## Instalar

Abra um terminal e cole (como seu usuário normal, **sem** sudo):

```sh
curl -fsSLO https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh && bash instalar.sh
```

O instalador:

1. confere se o leitor `27c6:538d` está no computador (e recusa qualquer outro);
2. baixa o driver já compilado (com conferência de integridade) — nada para compilar;
3. pede sua senha **uma vez** e instala em `/opt/fprint-538d`, ao lado do `fprintd` da sua
   distribuição (nenhum arquivo da distribuição é sobrescrito);
4. confere o firmware do leitor e desfaz tudo se não for compatível;
5. se você quiser, liga a digital no login, desbloqueio de tela, `sudo` e janelas de senha usando
   **o ajuste padrão da própria distribuição** — **a senha continua valendo sempre**;
6. guia o cadastro de um dedo (outros dedos depois, nas Configurações do sistema).

Nada mais no sistema é alterado. Depois de formatar: rodar o instalador, cadastrar, pronto.

Rodar de novo atualiza ou repara a instalação, mantendo as digitais.

**Desinstalar** (restaura o login e o `fprintd` original):

```sh
bash /opt/fprint-538d/share/fprint-538d/instalar.sh --desinstalar
```

Dicas: **encoste de leve** (apertar deforma a digital) e, no cadastro, varie a posição e gire um
pouco o dedo, para ele ser reconhecido em mais ângulos.

## Compatibilidade

| Família | Distribuições | Login (PAM) |
|---|---|---|
| Debian/Ubuntu | Ubuntu, Linux Mint, Pop!_OS, Zorin, elementary, Debian 12+ | `pam-auth-update` |
| Fedora | Workstation; Atomic: Silverblue, Kinoite, Bazzite, Aurora, Bluefin | `authselect` |
| Arch | Arch, CachyOS, EndeavourOS, Manjaro | sem ajuste padrão: login e bloqueio do GNOME/KDE usam sozinhos; `sudo` precisa de uma linha manual ([wiki do Arch](https://wiki.archlinux.org/title/Fprint)) |
| openSUSE | Tumbleweed, Leap 15.6, Aeon/Kalpa | `pam-config` |

Testado até agora: Linux Mint 22.3 num Inspiron 5590. As outras distribuições são verificadas
automaticamente (o driver carrega em cada uma), mas ainda não em notebook de verdade — **conte o seu
resultado** (modelo, distribuição, resultado do teste) nas
[issues](https://github.com/AndrePorrete/leitor-digital-goodix-538d/issues).

Notebooks conhecidos com esse leitor: Dell Inspiron 5590, 5402, 5409, 3501, 7506; Latitude 3410;
Vostro 3500. Qualquer computador com USB `27c6:538d` e firmware `GF5298_GM168SEC_APP_13016` é aceito.
**Nada é gravado no sensor.**

Como funciona, medições e o que deu errado no caminho: [PROTOCOLO.md](PROTOCOLO.md).
Créditos e licenças: ver [README.md](README.md#credits-and-licenses).
