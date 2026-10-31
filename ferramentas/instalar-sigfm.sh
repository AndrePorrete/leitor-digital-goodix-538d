#!/usr/bin/env bash
# Leitor de digital Goodix 27c6:538d — driver SIGFM (BaptistePignier) + fprintd 1.94.5 com aprendizado.
# Rodar como usuário normal (NÃO com sudo):  ./instalar-sigfm.sh
# Compila tudo como usuário e só usa sudo para instalar em /opt/fprint-538d.
# Não substitui pacotes do Mint. Desfazer: ./instalar-sigfm.sh --desfazer
set -euo pipefail
cd "$(dirname "$0")"
H="$PWD"
P=/opt/fprint-538d
DROPIN=/etc/systemd/system/fprintd.service.d/goodix-538d.conf

passo() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
[ "$(id -u)" -ne 0 ] || { echo "Rode sem sudo: ./instalar-sigfm.sh"; exit 1; }

if [ "${1:-}" = "--desfazer" ]; then
  sudo rm -f "$DROPIN"
  sudo rm -rf "$P"
  sudo systemctl daemon-reload
  sudo systemctl restart fprintd || true
  echo "Removido. Para voltar ao driver anterior: cd ~/.cache/instalar-goodix/repo && sudo ./install-driver.sh"
  exit 0
fi

passo "1/6 Apagando as digitais antigas (formato do driver anterior não serve no novo)"
fprintd-delete "$USER" 2>&1 | tail -2 || true

passo "2/6 Preparando o fprintd 1.94.5 com o patch de aprendizado"
git -C fprintd checkout -q -- .
git -C fprintd apply "$H"/goodix-538d/patches/fprintd/*.patch

passo "3/6 Compilando libfprint (SIGFM)"
rm -rf libfprint/build-opt fprintd/build stage
meson setup libfprint/build-opt libfprint --prefix=$P -Ddrivers=goodixtls53xd \
  -Dintrospection=false -Ddoc=false -Dgtk-examples=false \
  -Dudev_rules=disabled -Dudev_hwdb=disabled
ninja -C libfprint/build-opt

passo "4/6 Compilando fprintd"
PKG_CONFIG_PATH="$H/libfprint/build-opt/meson-uninstalled" \
  meson setup fprintd/build fprintd --prefix=$P -Dpam=false -Dman=false \
  -Dsystemd=false -Dgtk_doc=false -Dc_link_args=-Wl,-rpath,$P/lib/x86_64-linux-gnu
ninja -C fprintd/build
meson install -C libfprint/build-opt --destdir "$H/stage" >/dev/null
meson install -C fprintd/build --destdir "$H/stage" >/dev/null
[ -x "$H/stage$P/libexec/fprintd" ] || { echo "ERRO: fprintd não foi gerado"; exit 1; }

passo "5/6 Instalando em $P (pede a senha)"
# remove o driver anterior (infinytum) e o limiar que não se aplica mais
sudo bash "$H/../repo/install-driver.sh" --uninstall
sudo rm -rf "$P"
sudo cp -r "$H/stage$P" "$P"
sudo chown -R root:root "$P"
sudo chmod -R go-w "$P"
sudo mkdir -p "$(dirname "$DROPIN")"
sudo tee "$DROPIN" >/dev/null <<EOF
# Goodix 27c6:538d: fprintd + libfprint SIGFM com aprendizado (github.com/BaptistePignier/goodix-538d)
# Voltar ao fprintd do Mint: ~/.cache/instalar-goodix/sigfm/instalar-sigfm.sh --desfazer
[Service]
ExecStart=
ExecStart=$P/libexec/fprintd
EOF
# bibliotecas OpenCV usadas em tempo de execução (nomes do Ubuntu 24.04)
sudo apt-mark manual libopencv-core406t64 libopencv-features2d406t64 \
  libopencv-flann406t64 libopencv-imgproc406t64 >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart fprintd
sleep 1

passo "6/6 Verificando"
echo "fprintd em uso: $(systemctl show -p ExecStart fprintd | grep -o 'path=[^ ;]*')"
fprintd-list "$USER" | tail -2
cat <<'FIM'

Pronto. Agora cadastre o dedo (20 toques, espalhando pelo dedo todo; levante bem entre um e outro):

    fprintd-enroll -f right-index-finger

e teste:

    fprintd-verify -f right-index-finger
FIM
