# AGENTS.md — leitor-digital-goodix-538d

Para agentes (Claude Code etc.). Responder ao dono **em português**; ele não programa e não conhece
Linux: dar comandos prontos para colar, explicar em linguagem simples, nunca sugerir desistir.

## Estado (2026-10-30)
- Funciona no Dell Inspiron 5590 / Linux Mint 22.3: dedo certo 8/8, dedos errados 0/8 (máx. 38, limiar 60).
- Instalado em `/opt/fprint-538d` + drop-ins em `/etc/systemd/system/fprintd.service.d/`.
- Próxima tarefa: **instalador abrangente** (famílias Debian/Ubuntu, Fedora incl. Atomic/Bazzite, Arch/CachyOS, openSUSE)
  para **qualquer pessoa** com Inspiron 5590 + Goodix 538d, eficiente e simples. Requisitos em `PROTOCOLO.md` §7 e §7.1.

## Ler antes
1. `PROTOCOLO.md` — tudo o que foi feito, o que falhou e por quê, parâmetros finais.
2. `patches/` — mudanças sobre BaptistePignier/libfprint `goodix53xd-sigfm@d9f3ee1` e fprintd `v1.94.5`.
3. `ferramentas/instalar-sigfm.sh` — instalador atual (só Debian/Ubuntu, base para o novo).
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
