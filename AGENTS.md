# AGENTS.md — leitor-digital-goodix-538d

Para agentes (Claude Code etc.). Responder ao dono **em português**; ele não programa e não conhece
Linux: dar comandos prontos para colar, explicar em linguagem simples, nunca sugerir desistir.

## Estado (2026-10-30)
- Funciona no Dell Inspiron 5590 / Linux Mint 22.3: dedo certo 8/8, dedos errados 0/8 (máx. 38, limiar 60).
- Instalado em `/opt/fprint-538d` + drop-ins em `/etc/systemd/system/fprintd.service.d/`.
- **Instalador novo pronto, falta validar no hardware** (2026-10-31): `instalar.sh` (um arquivo; baixa
  `fprint-538d-x86_64.tar.gz` das releases ou usa `--pacote`; parte root via sudo/pkexec com `--interno`).
  Pacote: `construir/construir.sh` (contêiner ubuntu:22.04, OpenCV/OpenSSL estáticos; deps só glib, gusb, polkit).
  CI: `.github/workflows/pacote.yml` (compila, testa carga em 8 distros, release em tag `v*`).
  PAM testado em contêiner (Ubuntu, Debian, Fedora, Arch, Tumbleweed, Leap): `construir/testar-pam.sh`.
  Calibração DAC automática (patch 0002) — escolhe 7–8 neste sensor (simulado com os dumps).
  Confirmado ao vivo no 5590: `Finger DAC offset 0 -> 5 -> 8`.
- **Decisão do dono (2026-10-31): instalador "como um fabricante"** — só driver + pacotes da distro +
  ligar o ajuste PADRÃO de login com digital da distro (pam-auth-update fprintd / authselect / pam-config;
  Arch: não mexe). Nada de botão de ligar, perfil PAM próprio, teste rápido ou cadastro extra de ângulos.
  Versão 0.2.0 desfaz o que a 0.1.0 mudou (`desfazer_legado`).
- **Publicado (2026-10-31)**: repo PÚBLICO, release v0.3.2. Comando único no README/LEIAME
  (`sh -c "wget … || curl …" | bash`); instalação guiada em 5 passos com animação de espera; menu
  "Leitor de digital" (`/usr/local/bin/leitor-digital` + `.desktop`): cadastrar, testar, nível, apagar,
  atualizar, desinstalar. Nível de reconhecimento 70/60/55 em `/etc/fprint-538d.conf`.
  Histórico reescrito sem e-mail pessoal (backup: `~/.cache/fprint-538d-backup-historico.git`).
- **Conta GitHub (2026-10-31): pessoal `AndrePorrete`** (repo público + release v0.3.2). A conta de trabalho
  `AndrePorreteWEB` não deve ser usada aqui; histórico reescrito para `56418580+AndrePorrete@users.noreply.github.com`
  (backup antes da troca: `~/.cache/fprint-538d-backup-antes-conta-nova.git`). `gh` tem as duas contas; ativa: AndrePorrete.
- Falta: dono validar a v0.3.2 no Mint; relatos em Fedora/Arch reais.

## Ler antes
1. `PROTOCOLO.md` — tudo o que foi feito, o que falhou e por quê, parâmetros finais.
2. `patches/` — mudanças sobre BaptistePignier/libfprint `goodix53xd-sigfm@d9f3ee1` e fprintd `v1.94.5`.
3. `instalar.sh` + `construir/` — instalador multi-distro e geração do pacote.
4. Upstream com detalhes do protocolo USB/driver: github.com/BaptistePignier/goodix-538d (`AGENTS.md`).

## Regras rígidas
- Nunca gravar no flash do sensor (USB `0xA4 0xE0 0xF0 0xF4`); nunca rodar `run_538d.py`.
- Nunca versionar imagens/digitais (`*.pgm`, `*.variant`, dumps): dados biométricos.
- Não sobrescrever arquivos de pacotes da distro; instalar em `/opt/fprint-538d`.
- Admin só via `pkexec` (janela de senha) ou o dono roda no terminal; nunca pedir senha no chat,
  nunca criar sudo sem senha. Mudança em PAM: backup + plano de volta antes.
- No notebook do dono, toda alteração vai também para
  `~/Área de trabalho/Automação Linux/registro/alteracoes.md`.

## Ambiente do dono
- Claude Code roda no VSCodium Flatpak: comandos do host via `flatpak-spawn --host ...`;
  `/tmp` do sandbox não é visto pelo host (usar `~/.cache/instalar-goodix/`).
- Código-fonte de trabalho: `~/.cache/instalar-goodix/sigfm/{libfprint,fprintd}` (branch `inspiron5590`).
  Build: `ninja -C libfprint/build-opt` e `ninja -C fprintd/build`.
- Ver notas ao vivo: `journalctl -u fprintd -f | grep "best score"`.
- Leitor fica no botão de ligar: avisar para encostar de leve.

## Pendências combinadas com o dono
- **Depois que o instalador estiver pronto e validado**: apagar as imagens de digital usadas na análise
  (`~/.cache/instalar-goodix/{dump-real,dump-2053,dump-2113,coleta-1621,dumps}` e `*.npy`/`*.npz` ali),
  com `gio trash` e avisando o dono. Até lá, servem para validar o comparador.
- Modo de diagnóstico já desligado (2026-10-30); reativar só se precisar: ver `PROTOCOLO.md` §5.
