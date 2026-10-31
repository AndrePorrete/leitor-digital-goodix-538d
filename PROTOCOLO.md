# Protocolo — Leitor de digital Goodix 27c6:538d no Dell Inspiron 5590

Registro completo do que foi feito em 2026-10-30 para fazer o leitor funcionar com segurança no
Linux Mint 22.3, do que falhou e por quê, e do que precisa ser levado em conta no instalador
multi-distro (Mint, CachyOS, Bazzite).

Resultado final (teste guiado, 16 toques alternados, 2026-10-30 21:22):

| | Resultado |
|---|---|
| Dedo cadastrado (indicador direito) | **8/8 aceitos** (notas 76–92) |
| Dedos não cadastrados (médio D/E, polegar D, anelar D, indicador E) | **0/8 aceitos** (maior nota 38) |
| Limiar de aceite | 60 |

---

## 1. Hardware

| Item | Valor |
|---|---|
| Notebook | Dell Inspiron 5590 (leitor **dentro do botão de ligar**) |
| Sensor | Goodix USB `27c6:538d`, "Goodix TLS Fingerprint Sensor 53XD", match-on-host |
| Firmware exigido pelo driver | `GF5298_GM168SEC_APP_13016` (o deste notebook bate; nada foi gravado no sensor) |
| Imagem | 64×80 px de 12 bits → 60×76 px de 8 bits; área ~4×5 mm |
| Conteúdo da imagem | 4–5 cristas quase paralelas — pouquíssimos detalhes (minúcias) |
| Particularidade deste sensor | mais "claro" que o do autor do driver: satura na calibração com o DAC padrão → `GOODIX53XD_DAC_OFFSET=8` |

**Nunca** gravar no flash do sensor (comandos USB `0xA4`, `0xE0`, `0xF0`, `0xF4`) nem rodar
`run_538d.py` do goodix-fp-dump: apaga o firmware se PSK/firmware diferirem. Ver `AGENTS.md` do
projeto de origem (github.com/BaptistePignier/goodix-538d).

---

## 2. Componentes da solução final

```
fprintd 1.94.5 (+ patch deste repo)   -> /opt/fprint-538d/libexec/fprintd
libfprint fork SIGFM (+ patch)        -> /opt/fprint-538d/lib/x86_64-linux-gnu/libfprint-2.so.2
drop-in systemd                       -> /etc/systemd/system/fprintd.service.d/goodix-538d.conf (ExecStart)
                                         /etc/systemd/system/fprintd.service.d/calibracao.conf (DAC_OFFSET=8)
PAM                                   -> pam_fprintd.so da distro, max-tries=3 timeout=20
botão de ligar                        -> logind HandlePowerKey=ignore + Cinnamon button-power=nothing
digitais                              -> /var/lib/fprint/<usuário>/goodixtls53xd/0/<dedo>
```

Os pacotes `fprintd`/`libfprint` da distro **continuam instalados** (D-Bus, polkit, `pam_fprintd.so`
e `fprintd-*` vêm deles); só o executável do serviço é trocado pelo drop-in. Atualizações da distro
não quebram nada, exceto se mudarem o nome do serviço ou a interface D-Bus.

Origem do código:

| Repositório | Base | Patch |
|---|---|---|
| github.com/BaptistePignier/libfprint, branch `goodix53xd-sigfm` | `d9f3ee1` | `patches/libfprint/0001-*.patch` |
| gitlab.freedesktop.org/libfprint/fprintd | tag `v1.94.5` | `patches/fprintd/0001-*.patch` (inclui o patch de aprendizado do goodix-538d) |

---

## 3. Cronologia (o que foi tentado, em ordem)

### 3.1 Driver infinytum (NBIS) — descartado
- Roteiro github.com/01xcampos/goodix-27c6-538d-ubuntu (libfprint infinytum, branch `driver/538d`).
- Build precisou de `libgusb-dev libssl-dev` e `-Ddoc=false -Dintrospection=false -Dgtk-examples=false`.
- `fprint-list-supported-devices` dá segfault → verificar o ID por grep em `goodix53xd.h`.
- Sensor reconhecido e cadastro feito, mas **aceitava qualquer dedo**: limiar bozorth3 vinha 24.
  Subir para 40 não resolveu: as notas NBIS ficavam 0–18 para qualquer dedo, certo ou errado.
  **Motivo:** NBIS depende de minúcias; com 4–5 cristas paralelas em 4×5 mm quase não há minúcias.

### 3.2 Fork SIGFM (BaptistePignier) — base mantida
- libfprint `goodix53xd-sigfm` + fprintd 1.94.5 com patch que salva a digital "aprendida".
  Instalação isolada em `/opt/fprint-538d` (script `ferramentas/instalar-sigfm.sh`).
- Deps de build (Ubuntu 24.04): `meson ninja-build gcc libglib2.0-dev libgusb-dev libssl-dev
  libopencv-dev doctest-dev libpolkit-gobject-1-dev libsystemd-dev libdbus-1-dev cmake`.
  Runtime: `libopencv-{core,features2d,flann,imgproc}406t64` (marcados como manuais no apt).
- Erro do script original: `git apply` com caminho relativo do patch → usar caminho absoluto.

### 3.3 Calibração do sensor
- Imagens saturadas (~25% dos pixels a +20 de DAC) → cadastro difícil, poucos toques aceitos.
- Solução: `GOODIX53XD_DAC_OFFSET=8` no drop-in `calibracao.conf`.

### 3.4 Travamento no cadastro — corrigido no driver
- Se o dedo encostava logo após a calibração, o quadro de "ruído de fundo" saía com o dedo (ruído
  ~3000): o limiar de detecção ficava inalcançável e o cadastro travava para sempre.
- Patch: ruído > 64 → recalibra (`GOODIX53XD_MAX_BG_NOISE`).

### 3.5 SIGFM (SIFT) não separa dedos — comparador substituído
- Com dumps rotulados (`GOODIX53XD_DUMP_DIR`), o SIGFM dava notas parecidas para dedos diferentes:
  cristas paralelas geram pontos SIFT "genéricos". Aceitava dedo errado com facilidade.
- Ferramenta de coleta rotulada (`ferramentas/coletar.c` + `coletar.sh`): 28 toques de 5 dedos.
- **Comparador novo** (em `sigfm.cpp`, guarda a imagem 8 bits dentro da digital):
  1. pré-processamento: mediana 3×3, diferença de gaussianas (σ1 − σ4), normalização z;
  2. alinhamento: miolo de 60% da imagem A girado θ, `matchTemplate` (correlação normalizada)
     sobre B com borda; e o mesmo de B sobre A girado −θ (**giro coerente nos dois sentidos**);
     θ ∈ [−15°, 15°] em passos de 3°;
  3. verificação local: com o melhor alinhamento, correlação em blocos 12×12 (passo 6, ≥95% de
     cobertura, ≥6 blocos) → **1º quartil** das correlações dos blocos;
  4. nota = média das duas correlações × q25 × 100. Nota da digital = **maior** entre todas as
     imagens do cadastro.
- Evolução das regras (`ferramentas/analise/exp3.py`, cadastro real × toques rotulados):

  | Regra | Dedo errado (máx.) | Dedo certo acima disso |
  |---|---|---|
  | giros independentes em cada sentido (1ª versão) | 0,856 | 83% |
  | giro coerente ±30° | 0,854 | — |
  | giro coerente ±15° | 0,757 | — |
  | coerente ±30° × q25 dos blocos | 0,554 | 100% |
  | **coerente ±15° × q25 (final, "regra E")** | **0,505** | **100%**, margem +0,325 |

  **Lição:** quem separa os dedos é a verificação em blocos (q25) e a coerência entre sentidos.
  Com giro livre e sentidos independentes, cristas paralelas "encaixam" em qualquer dedo
  (o polegar chegou a 86). O limite de 15° ajuda pouco; ele vale **por imagem do cadastro**, então
  ângulos diferentes são cobertos cadastrando o dedo em vários ângulos (ver 3.8).
- Limiar: primeiro 80/75 (1ª versão), final **60** com a regra E (dedo errado máx. 51 nos testes).

### 3.6 Aprendizado contaminado — trava de nota
- O fork adiciona cada toque aceito ao cadastro (até 50 imagens, como o driver do Windows).
  Um dedo errado aceito por pouco (82 na 1ª versão) entrou no cadastro e passou a abrir.
- Patch: aprende só se a maior nota ≥ `FPRINT_LEARN_MIN` (padrão **75**); o limiar de aceite é 60.
  Também: cadastro de 20 → **15** toques.

### 3.7 PAM
- O app Fingwit do Mint cria o perfil `pam_fprintd.so max-tries=1 timeout=15` → trocado para
  `max-tries=3 timeout=20` (backups `fingwit.original`, `common-auth.antes-digital`).
  Atualização do pacote Fingwit pode voltar para 1 tentativa.

### 3.8 Cobertura de ângulos — cadastro extra do mesmo dedo
- O driver do Windows aceita qualquer ângulo porque usa minúcias. Aqui, cada imagem do cadastro
  cobre ±15°; para outros ângulos, cadastrar o **mesmo dedo de novo em outra vaga** girando o dedo
  (`ferramentas/cadastrar-angulos.sh`, vaga `right-thumb` usada só como rótulo).
- O fprintd recusava com `enroll-duplicate` → patch: duplicata **do mesmo usuário** é permitida;
  de outro usuário continua barrada.
- Armadilha: `fprintd-verify` **sem `-f`** testa só o primeiro dedo da lista. Para testar como o
  PAM (todos os dedos), usar `fprintd-verify -f any`.

### 3.9 Botão de ligar
- Apertar o leitor com força aciona o botão de ligar → o notebook suspendia no meio do cadastro.
- Cinnamon: `button-power` = `nothing`; logind: `HandlePowerKey=ignore` (tela de login).
  Segurar 4 s continua desligando à força. **Dica ao usuário: encostar de leve** (pressão deforma
  as cristas e piora a nota).

---

## 4. Parâmetros finais

| Parâmetro | Valor | Onde |
|---|---|---|
| Limiar de aceite | 60 (0–100) | `goodix53xd.c` `bz3_threshold`; env `FPRINT_BZ3_THRESHOLD` |
| Limiar de aprendizado | 75 | env `FPRINT_LEARN_MIN` (`fpi-image-device.c`) |
| Máx. imagens por digital | 50 | `GOODIX53XD_TEMPLATE_MAX` |
| Toques no cadastro | 15 | `GOODIX53XD_ENROLL_STAGES` |
| Pontos SIFT mínimos | 33 (abaixo: pede outro toque) | `GOODIX53XD_MIN_KEYPOINTS` |
| Giro | ±15°, passo 3° | `ncc_match_score` em `sigfm.cpp` |
| Blocos | 12×12, passo 6, 1º quartil | `block_q25` em `sigfm.cpp` |
| DAC offset | 8 (específico deste sensor) | env `GOODIX53XD_DAC_OFFSET` |
| Ruído máx. pós-calibração | 64 | `GOODIX53XD_MAX_BG_NOISE` |
| PAM | 3 tentativas, 20 s | perfil PAM |

---

## 5. Ferramentas (pasta `ferramentas/`)

| Arquivo | Uso |
|---|---|
| `testar.sh` | teste guiado: 16 toques alternando dedo certo/errado, tabela com notas (`-f any`, 25 s por toque) |
| `cadastrar-angulos.sh` | segundo cadastro do indicador em ângulos variados |
| `coletar.c` / `coletar.sh` | coleta rotulada de imagens por dedo (para fprintd, usa a lib direto; root) |
| `instalar-sigfm.sh` | instalador usado no Mint (base para o instalador novo) |
| `analise/exp3.py` | comparação de regras de decisão com imagens rotuladas |
| `analise/teste_ncc.cpp` | testa o comparador C++ real (`libsigfm.a`) sobre imagens |
| `analise/q.py`, `q2.py`, `exp2.py`, `rotular.py` | reanálises pontuais (mapear dumps → rótulos por horário) |

Imagens e digitais são **dados biométricos**: ficam fora do git (`.gitignore`).

Ver notas: `journalctl -u fprintd | grep "best score"` (precisa `G_MESSAGES_DEBUG=libfprint-print`).

---

## 6. Problemas operacionais encontrados

| Sintoma | Causa / solução |
|---|---|
| `Device was already claimed` | outro programa (Fingwit, cadastro aberto) segurando o leitor → fechar / `systemctl restart fprintd` |
| `enroll-duplicate` | dedo já cadastrado → patch do fprintd (3.8) |
| `Failed to detect minutiae: No enough keypoints` | toque pobre (polegar quase sempre); pede outro toque |
| `failed to scan: Command timed out: 0x80` | ocasional entre toques, inofensivo |
| notebook suspende ao apertar | botão de ligar (3.9) |
| sessão do Claude Code em Flatpak (VSCodium) | comandos do sistema via `flatpak-spawn --host`; admin via `pkexec`; `/tmp` do sandbox não é visível no host |

---

## 7. Plano para o instalador multi-distro

Requisitos levantados para Mint, CachyOS (Arch) e Bazzite (Fedora Atomic):

1. **Compilar dentro de contêiner** (podman/distrobox, imagem Fedora ou Arch) para não sujar o
   sistema e funcionar no Bazzite (sistema de arquivos `/usr` somente leitura). Gerar um pacote
   `/opt/fprint-538d` autocontido.
2. **OpenCV estático e mínimo** (core, imgproc, features2d, flann) dentro da libfprint: o Bazzite
   não tem OpenCV na imagem, e as versões variam entre distros. Restante dinâmico (glib, gusb,
   openssl, pixman, polkit, dbus) — presentes nas três distros porque o fprintd da distro já usa.
3. `--libdir=lib` + rpath `/opt/fprint-538d/lib` (Debian usa `x86_64-linux-gnu`, Fedora `lib64`).
4. **Bazzite**: `/opt` → `/var/opt` (gravável, ok); `/etc` gravável (drop-ins ok). **SELinux**:
   o binário em `/opt` precisa de contexto de execução aceitável para o serviço
   (`semanage fcontext -a -t fprintd_exec_t '/opt/fprint-538d/libexec/fprintd'` + `restorecon`),
   testar. PAM via `authselect enable-feature with-fingerprint`.
5. **CachyOS**: instalar `fprintd` do repositório (traz `pam_fprintd.so`); PAM manual (ver
   `config/pam/README.md`); KDE é o padrão (SDDM/kscreenlocker já suportam digital).
6. Detectar o sensor (`lsusb -d 27c6:538d`) e o firmware antes de instalar; recusar outros.
7. **Calibração automática do DAC** em vez do 8 fixo: medir a saturação do quadro sem dedo e
   escolher o menor offset sem saturar (o 8 é deste sensor; o do autor do driver usa 0).
8. Botão de ligar: oferecer `HandlePowerKey=ignore` + ajuste do ambiente gráfico (Cinnamon,
   GNOME, KDE) só em notebooks com leitor no botão.
9. Desinstalar = remover `/opt/fprint-538d`, drop-ins, regra SELinux, desfazer PAM a partir de
   backup; digitais em `/var/lib/fprint` (formato próprio do fork, não servem no fprintd original).
10. Após instalar: guiar cadastro (15 toques, de leve) + cadastro de ângulos + `testar.sh`.

Digitais cadastradas **não** migram entre formatos de comparador; após mudar o comparador é preciso
recadastrar (a digital guarda as imagens, então reprocessar é possível no futuro).
