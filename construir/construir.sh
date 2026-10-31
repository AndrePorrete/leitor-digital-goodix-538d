#!/usr/bin/env bash
# Builds the self-contained bundle installed in /opt/fprint-538d:
#   libexec/fprintd          fprintd 1.94.5 + patch, rpath $ORIGIN/../lib
#   lib/libfprint-2.so.2     libfprint SIGFM fork + patches, OpenCV and OpenSSL linked statically
#   share/fprint-538d/       installer copy, licenses, source list
# Runs as root inside an ubuntu:22.04 container (glibc 2.35: the bundle then runs on any newer
# distribution). Use construir/no-conteiner.sh on a host, or the GitHub workflow.
# Output: dist/fprint-538d-x86_64.tar.gz and .sha256
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$REPO/dist}
WORK=${WORK:-/var/tmp/fprint-538d-build}
DEPS=$WORK/deps
PREFIX=/opt/fprint-538d
JOBS=$(nproc)

LIBFPRINT_URL=https://github.com/BaptistePignier/libfprint.git
LIBFPRINT_REV=d9f3ee1426a733b9f68807151f0a71cdf7176ae6 # branch goodix53xd-sigfm
FPRINTD_URL=https://gitlab.freedesktop.org/libfprint/fprintd.git
FPRINTD_TAG=v1.94.5
OPENSSL_VER=3.0.15
OPENSSL_SHA256=23c666d0edf20f14249b3d8f0368acaee9ab585b09e1de82107c66e1f3ec9533
OPENCV_VER=4.10.0
OPENCV_SHA256=b2171af5be6b26f7a06b1229948bbb2bdaa74fcf5cd097e0af6378fce50a6eb9

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }

fetch() { # url sha256 file
  if [ ! -f "$3" ]; then
    curl -fL --retry 3 -o "$3.part" "$1"
    mv "$3.part" "$3"
  fi
  echo "$2  $3" | sha256sum -c --quiet
}

step "Build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential pkg-config cmake ninja-build meson git curl ca-certificates perl patchelf file \
  libglib2.0-dev libgusb-dev libpolkit-gobject-1-dev libsystemd-dev libdbus-1-dev doctest-dev \
  python3 gettext >/dev/null

mkdir -p "$WORK" "$DEPS" "$OUT"
cd "$WORK"

step "OpenSSL $OPENSSL_VER (static)"
if [ ! -f "$DEPS/lib/libcrypto.a" ]; then
  fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" \
    "$OPENSSL_SHA256" openssl.tar.gz
  rm -rf openssl && mkdir openssl && tar -xzf openssl.tar.gz -C openssl --strip-components=1
  (cd openssl && ./Configure linux-x86_64 no-shared no-tests no-module -fPIC \
     --prefix="$DEPS" --libdir=lib --openssldir=/etc/ssl >/dev/null &&
   make -j"$JOBS" >/dev/null && make install_sw >/dev/null)
  mkdir -p "$DEPS/licencas" && cp openssl/LICENSE.txt "$DEPS/licencas/openssl-Apache-2.0.txt"
fi

step "OpenCV $OPENCV_VER (static: core, imgproc, features2d, flann)"
if [ ! -f "$DEPS/lib/libopencv_core.a" ]; then
  fetch "https://github.com/opencv/opencv/archive/refs/tags/$OPENCV_VER.tar.gz" "$OPENCV_SHA256" opencv.tar.gz
  rm -rf opencv && mkdir opencv && tar -xzf opencv.tar.gz -C opencv --strip-components=1
  cmake -S opencv -B opencv/build -G Ninja -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS" \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_LIST=core,imgproc,features2d,flann \
    -DOPENCV_LIB_INSTALL_PATH=lib -DOPENCV_3P_LIB_INSTALL_PATH=lib \
    -DBUILD_ZLIB=ON -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_OPENCL=OFF -DWITH_TBB=OFF \
    -DWITH_EIGEN=OFF -DWITH_LAPACK=OFF -DWITH_PROTOBUF=OFF -DWITH_ADE=OFF -DWITH_VA=OFF \
    -DWITH_OPENEXR=OFF -DWITH_FFMPEG=OFF -DWITH_GSTREAMER=OFF -DWITH_GTK=OFF -DWITH_QT=OFF \
    -DWITH_V4L=OFF -DWITH_1394=OFF -DWITH_IMGCODEC_HDR=OFF -DCV_TRACE=OFF \
    -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_opencv_apps=OFF \
    -DBUILD_JAVA=OFF -DBUILD_opencv_python3=OFF -DOPENCV_GENERATE_PKGCONFIG=OFF >/dev/null
  ninja -C opencv/build >/dev/null
  ninja -C opencv/build install >/dev/null
  mkdir -p "$DEPS/licencas" && cp opencv/LICENSE "$DEPS/licencas/opencv-Apache-2.0.txt"
fi

# pkg-config files linking the static archives explicitly
mkdir -p "$DEPS/pkgconfig"
cat >"$DEPS/pkgconfig/opencv4.pc" <<EOF
Name: OpenCV
Description: OpenCV $OPENCV_VER static subset
Version: $OPENCV_VER
Cflags: -I$DEPS/include/opencv4
Libs: $DEPS/lib/libopencv_features2d.a $DEPS/lib/libopencv_flann.a $DEPS/lib/libopencv_imgproc.a $DEPS/lib/libopencv_core.a $DEPS/lib/libzlib.a -ldl -lpthread
EOF
cat >"$DEPS/pkgconfig/openssl.pc" <<EOF
Name: OpenSSL
Description: OpenSSL $OPENSSL_VER static
Version: $OPENSSL_VER
Cflags: -I$DEPS/include
Libs: $DEPS/lib/libssl.a $DEPS/lib/libcrypto.a -ldl -pthread
EOF
export PKG_CONFIG_PATH=$DEPS/pkgconfig

step "libfprint (SIGFM fork) + patches"
rm -rf libfprint
git clone -q "$LIBFPRINT_URL" libfprint
git -C libfprint checkout -q "$LIBFPRINT_REV"
for p in "$REPO"/patches/libfprint/*.patch; do git -C libfprint apply "$p"; done
meson setup libfprint/build libfprint --prefix=$PREFIX --libdir=lib --buildtype=release \
  -Ddrivers=goodixtls53xd -Dintrospection=false -Ddoc=false -Dgtk-examples=false \
  -Dudev_rules=disabled -Dudev_hwdb=disabled | tail -15
ninja -C libfprint/build

step "fprintd $FPRINTD_TAG + patch"
rm -rf fprintd
git -c advice.detachedHead=false clone -q --depth 1 --branch "$FPRINTD_TAG" "$FPRINTD_URL" fprintd
for p in "$REPO"/patches/fprintd/*.patch; do git -C fprintd apply "$p"; done
PKG_CONFIG_PATH="$WORK/libfprint/build/meson-uninstalled:$PKG_CONFIG_PATH" \
  meson setup fprintd/build fprintd --prefix=$PREFIX --libdir=lib --sysconfdir=/etc --buildtype=release \
  -Dpam=false -Dman=false -Dsystemd=false -Dgtk_doc=false
ninja -C fprintd/build src/fprintd

step "Bundle"
VERSION=$(cat "$REPO/VERSION")
STAGE=$WORK/stage/fprint-538d
rm -rf "$WORK/stage" && mkdir -p "$STAGE"/{libexec,lib,share/fprint-538d/licencas}
cp fprintd/build/src/fprintd "$STAGE/libexec/"
cp -P libfprint/build/libfprint/libfprint-2.so libfprint/build/libfprint/libfprint-2.so.2 libfprint/build/libfprint/libfprint-2.so.2.0.0 "$STAGE/lib/"
rm -f "$STAGE/lib/libfprint-2.so"
patchelf --set-rpath '$ORIGIN/../lib' "$STAGE/libexec/fprintd"
strip --strip-unneeded "$STAGE/libexec/fprintd" "$STAGE"/lib/libfprint-2.so.*.*
cp "$REPO/instalar.sh" "$STAGE/share/fprint-538d/"
cp "$REPO/ferramentas/testar.sh" "$REPO/ferramentas/cadastrar-angulos.sh" "$STAGE/share/fprint-538d/" 2>/dev/null || true
cp "$REPO/LICENSE" "$STAGE/share/fprint-538d/licencas/fprint-538d-scripts.txt" 2>/dev/null || true
cp libfprint/COPYING "$STAGE/share/fprint-538d/licencas/libfprint-LGPL-2.1.txt"
cp fprintd/COPYING "$STAGE/share/fprint-538d/licencas/fprintd-GPL-2.0.txt"
cp "$DEPS"/licencas/*.txt "$STAGE/share/fprint-538d/licencas/"
echo "$VERSION" >"$STAGE/share/fprint-538d/VERSAO"
cat >"$STAGE/share/fprint-538d/FONTES.txt" <<EOF
fprint-538d $VERSION — source code (GPL/LGPL: the complete corresponding source is listed here)
  bundle scripts and patches: https://github.com/AndrePorrete/leitor-digital-goodix-538d
  libfprint: $LIBFPRINT_URL @ $LIBFPRINT_REV + patches/libfprint/*.patch
  fprintd:   $FPRINTD_URL @ $FPRINTD_TAG + patches/fprintd/*.patch
  OpenSSL $OPENSSL_VER (static), OpenCV $OPENCV_VER (static: core imgproc features2d flann)
  build: construir/construir.sh in ubuntu:22.04
EOF

step "Checks"
echo "NEEDED:"; readelf -d "$STAGE/libexec/fprintd" "$STAGE/lib/libfprint-2.so.2" | awk '/NEEDED/{print "  "$5}' | sort -u
if readelf -d "$STAGE/lib/libfprint-2.so.2" | grep -qE 'opencv|libssl|libcrypto'; then
  echo "ERROR: OpenCV/OpenSSL linked dynamically"; exit 1
fi
LD_BIND_NOW=1 "$STAGE/libexec/fprintd" --help >/dev/null && echo "fprintd loads OK"

tar -C "$WORK/stage" --owner=0 --group=0 -czf "$OUT/fprint-538d-x86_64.tar.gz" fprint-538d
(cd "$OUT" && sha256sum fprint-538d-x86_64.tar.gz >fprint-538d-x86_64.tar.gz.sha256)
ls -l "$OUT"
