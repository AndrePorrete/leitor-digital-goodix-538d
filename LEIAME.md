# fprint-538d — leitor de digital Goodix 27c6:538d no Linux

*[English version: README.md](README.md)*

Faz o leitor de digital Goodix `27c6:538d` (botão de ligar do Dell Inspiron 5590 e de outros
notebooks Dell) funcionar no Linux: login, desbloqueio de tela, `sudo` e janelas de senha.

| Teste guiado num Inspiron 5590 | |
|---|---|
| Dedo cadastrado | 8/8 aceitos |
| Outros dedos | 0/8 aceitos |

## Instalar

1. Abra o **Terminal**: aperte juntas as teclas **Ctrl + Alt + T** (ou procure "Terminal" no menu).
2. Copie a linha abaixo (botão de copiar à direita dela), cole no Terminal com **Ctrl + Shift + V**
   e aperte **Enter**:

```sh
bash <(wget -qO- https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh || curl -fsSL https://raw.githubusercontent.com/AndrePorrete/leitor-digital-goodix-538d/main/instalar.sh)
```

3. Siga a tela. O instalador explica cada passo e mostra quando está trabalhando:
   1. confere se o computador tem o leitor `27c6:538d` (recusa qualquer outro);
   2. faz duas perguntas — usar a digital no login (a senha continua valendo) e o nível de
      reconhecimento (para dedos com calo, escolha **Tolerante**);
   3. baixa o driver já compilado;
   4. pede **a sua senha uma vez** (enquanto digita, nada aparece — é normal) e instala;
   5. guia o cadastro do dedo: 15 toques **leves** no leitor.

Nada mais no sistema é alterado e nada é gravado no leitor. Depois de formatar, é só repetir.

### Depois de instalado

Abra o menu de aplicativos e procure **Leitor de digital** (ou digite `leitor-digital` num
terminal). Lá você cadastra outros dedos, testa, muda o nível de reconhecimento, atualiza ou
desinstala — sem digitar comandos.

## Dedos difíceis (calos, pele seca)

Quem toca instrumento de corda, trabalha com as mãos ou tem pele muito seca pode ter dedos que o
leitor reconhece mal. Nesse caso:

1. **Cadastre os dedos com menos calo** (por exemplo, os que não apertam as cordas). Pode cadastrar
   vários: qualquer um deles é aceito.
2. **Escolha o nível de reconhecimento** — o instalador pergunta durante a instalação; para mudar
   depois:

   ```sh
   leitor-digital      # opção 3 do menu
   ```

   Sem perguntas: `--nivel tolerante` (ou `padrao`, `rigoroso`), na instalação ou junto com `--ajustar`.

   | Nível | Nota mínima | Quando usar |
   |---|---|---|
   | Rigoroso | 70 | quer o máximo de segurança, aceita repetir o toque |
   | Padrão | 60 | a maioria das pessoas |
   | Tolerante | 55 | dedos com calo ou pele seca |

   Nos testes, dedos errados tiraram no máximo 51 — o nível Tolerante ainda fica acima disso, mas
   com menos folga. O ajuste é mantido ao atualizar.
3. Cadastre de novo quando os calos mudarem bastante. Com o uso, o leitor também vai aprendendo
   sozinho com os toques bem reconhecidos (nota ≥ 75).

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
