# Leitor de digital Goodix 27c6:538d no Linux (Dell Inspiron 5590)

Faz o leitor de digital do botão de ligar do Dell Inspiron 5590 (Goodix `27c6:538d`) funcionar no
Linux com segurança: login, desbloqueio de tela, `sudo` e janelas de senha.

| Teste guiado (2026-10-30) | |
|---|---|
| Dedo cadastrado | 8/8 aceitos |
| Outros dedos | 0/8 aceitos |

Base: driver SIGFM da comunidade ([BaptistePignier/goodix-538d](https://github.com/BaptistePignier/goodix-538d)),
com um comparador novo (correlação alinhada + verificação por blocos), aprendizado com trava de nota,
correção de travamento no cadastro e cadastro extra do mesmo dedo para cobrir mais ângulos.

- **[PROTOCOLO.md](PROTOCOLO.md)** — o que foi feito, o que falhou, parâmetros e plano do instalador.
- `patches/` — alterações sobre libfprint (fork SIGFM) e fprintd 1.94.5.
- `config/` — drop-ins do systemd, logind (botão de ligar) e notas de PAM.
- `ferramentas/` — teste guiado, cadastro de ângulos, coleta e análise.

Status: funcionando no Linux Mint 22.3. Instalador para Mint, CachyOS e Bazzite: em desenvolvimento.

> Não use em sensores Goodix diferentes do `27c6:538d` com firmware `GF5298_GM168SEC_APP_13016`.
> Nada é gravado no sensor.

Licenças: os patches derivam de libfprint (LGPL-2.1+) e fprintd (GPL-2.0+) e seguem essas licenças.
