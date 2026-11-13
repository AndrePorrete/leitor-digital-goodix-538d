# Leitor de digital Goodix 27c6:538d no Linux

*[English version: README.md](README.md)*

Faz funcionar no Linux o leitor de digital que fica no **botão de ligar** do Dell Inspiron 5590
(e de outros notebooks Dell com o mesmo leitor): entrar no sistema, desbloquear a tela, `sudo` e
janelas que pedem senha. A senha continua valendo sempre; a digital é só um atalho.

| Teste guiado num Inspiron 5590 | |
|---|---|
| Dedo cadastrado | 8 de 8 aceitos |
| Outros dedos | 0 de 8 aceitos |

## Instalar (5 minutos)

1. Abra o **Terminal**: aperte juntas as teclas **Ctrl + Alt + T** (ou procure "Terminal" no menu
   de aplicativos).
2. Copie a linha abaixo (botão de copiar à direita dela), cole no Terminal com
   **Ctrl + Shift + V** e aperte **Enter**:

```sh
sh -c "wget -qO- https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh || curl -fsSL https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh" | bash
```

3. Siga a tela. Ela explica cada passo e mostra quando está trabalhando:
   1. confere se o computador tem o leitor `27c6:538d` (se não tiver, para sem mudar nada);
   2. faz duas perguntas: usar a digital para entrar no sistema e o nível de reconhecimento
      (para dedos com calo ou pele seca, escolha **Tolerante**);
   3. baixa o driver já pronto (com conferência de integridade);
   4. pede **a sua senha uma vez** (enquanto você digita, nada aparece na tela; é normal) e instala;
   5. guia o cadastro do dedo: 15 toques **leves** no botão de ligar.

Pronto. Na próxima vez que o sistema pedir senha, encoste o dedo cadastrado no botão.

**Dicas para o toque:** encoste de leve, sem apertar o botão; dedo limpo e seco; varie um pouco a
posição durante o cadastro (ponta, centro, um pouco de lado).

## Depois de instalado: o menu "Leitor de digital"

Abra o menu de aplicativos e procure **Leitor de digital** (ou digite `leitor-digital` num
terminal). Tudo é feito por ali, sem digitar comandos:

| Opção | Para quê |
|---|---|
| 1. Cadastrar um dedo | outro dedo, ou o mesmo de novo (por exemplo, com o dedo mais seco) |
| 2. Testar a digital | um toque, mostra se reconheceu |
| 3. Nível de reconhecimento | Rigoroso, Padrão ou Tolerante (veja abaixo) |
| 4. Apagar digitais | remove os dedos cadastrados |
| 5. Atualizar ou reparar | baixa a versão mais nova e conserta a instalação |
| 6. Desinstalar | tira tudo e devolve o sistema como era |

Depois de formatar ou reinstalar o sistema, é só rodar a linha de instalação de novo.

## Nível de reconhecimento

| Nível | Nota mínima | Quando usar |
|---|---|---|
| Rigoroso | 70 | quer o máximo de segurança e aceita repetir o toque às vezes |
| Padrão | 60 | a maioria das pessoas |
| Tolerante | 55 | dedos com calo, pele seca ou que costumam falhar |

Nos testes, dedos errados tiraram no máximo 51: o Tolerante ainda fica acima disso, com menos folga.
O nível escolhido é mantido nas atualizações. Com o uso, o leitor também aprende sozinho com os
toques bem reconhecidos.

## Sistemas

Precisa de computador **x86_64** (Intel/AMD de 64 bits), **systemd** e **glibc 2.33 ou mais nova**.
O instalador confere tudo isso antes de mudar qualquer coisa.

**Testado em notebook de verdade** (Inspiron 5590): Linux Mint 22.3 e CachyOS.

**Verificado a cada versão em contêiner** (o driver carrega, o instalador reconhece o sistema e
liga e desliga o login com digital sem deixar resto):

| Família | Sistemas verificados | Como o login com digital é ligado |
|---|---|---|
| Ubuntu / Debian | Ubuntu 22.04, 24.04 e 26.04; Linux Mint 22; Debian 12 e 13 | `pam-auth-update` (o ajuste padrão do sistema) |
| Fedora | Fedora 42, 43 e 44; Fedora Kinoite 43; Bazzite; AlmaLinux 9 e 10 | `authselect` |
| Arch | Arch Linux, Manjaro, CachyOS | não há ajuste padrão (veja "Problemas comuns") |
| openSUSE | Tumbleweed; Leap 15.6 e 16.0 | `pam-config` |

**Devem funcionar** (mesma família, ainda não verificados): Pop!_OS, Zorin OS, elementary OS,
KDE neon, Nobara, Fedora Silverblue, Aurora, Bluefin, Rocky Linux 9+, EndeavourOS, Garuda,
openSUSE Aeon e Kalpa.

**Não funcionam:** sistemas de 32 bits ou ARM; sistemas antigos com glibc anterior à 2.33 (por
exemplo Ubuntu 20.04, Debian 11, Linux Mint 20); sistemas sem systemd (Devuan, Void, Artix) ou com
musl (Alpine).

**Notebooks** conhecidos com esse leitor: Dell Inspiron 5590, 5402, 5409, 3501 e 7506;
Latitude 3410; Vostro 3500. Qualquer computador com o leitor USB `27c6:538d` e firmware
`GF5298_GM168SEC_APP_13016` é aceito. **Nada é gravado no leitor.**

## Problemas comuns

- **Não reconhece o dedo:** encoste mais de leve e espere um instante. Se falha muito, escolha o
  nível **Tolerante** (menu, opção 3) e cadastre o mesmo dedo de novo (opção 1), de preferência com o
  dedo como ele costuma estar no dia a dia (por exemplo, seco). Dá para cadastrar vários dedos.
- **O notebook desliga ou suspende quando encosto o dedo:** você apertou o botão. O toque é só
  encostar. Se quiser, desligue a ação do botão em *Configurações > Energia > Botão de ligar*
  ("Não fazer nada"); segurar o botão por 4 segundos continua desligando à força.
- **Arch, Manjaro, CachyOS, EndeavourOS:** a tela de login e a de bloqueio do GNOME e do KDE já
  usam a digital sozinhas. Para o `sudo` e as janelas de senha, siga a
  [wiki do Arch](https://wiki.archlinux.org/title/Fprint) (uma linha em `/etc/pam.d/sudo` e
  `/etc/pam.d/polkit-1`).
- **Já tentei outro tutorial antes:** alguns scripts gravam outro driver por cima da biblioteca de
  digital do sistema (`libfprint`). O instalador percebe e oferece devolver o original; este driver
  não depende dela.
- **Depois de uma atualização grande do sistema parou de funcionar:** abra o menu "Leitor de
  digital" e escolha **5. Atualizar ou reparar**.
- **Quero tirar tudo:** menu "Leitor de digital", opção **6. Desinstalar**.

## Conte como foi

Funcionou (ou não) no seu notebook? Abra um relato em
[Issues](https://github.com/AndrePorrete/leitor-digital-goodix-538d/issues/new/choose) com o modelo
do notebook, o sistema e o resultado do teste. Relatos de Fedora, Arch e openSUSE em notebook de
verdade ajudam muito.

## Para quem quer saber mais

- Driver: versão comunitária SIGFM da `libfprint` para este leitor
  ([BaptistePignier/goodix-538d](https://github.com/BaptistePignier/goodix-538d)), com um novo
  comparador de digitais (o leitor mostra só 4 ou 5 sulcos do dedo, pouco para os algoritmos
  comuns), aprendizado só com toques confiáveis, calibração automática do sensor e correções de
  travamento e de queda.
- `fprintd` 1.94.5 com um ajuste para guardar o que o leitor aprende. Tudo fica em
  `/opt/fprint-538d`, ao lado dos pacotes do sistema, sem sobrescrever nada.
- Código-fonte das mudanças: `patches/`; geração do pacote: `construir/`; instalador: `instalar.sh`.
  Créditos e licenças: [README.md](README.md#credits-and-licenses).
