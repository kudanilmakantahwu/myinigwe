#!/bin/sh
# Build linux-postmarketos-qcom-sdm660 inside an Alpine container.
# Runs as root inside `alpine:edge`, with the repo mounted at /work.
set -eu

KVER="7.0.14"
FLAVOR="postmarketos-qcom-sdm660"
TAG="v${KVER}-sdm660"
TARBALL="linux-${TAG}.tar.gz"
URL="https://github.com/sdm660-mainline/linux/archive/refs/tags/${TAG}.tar.gz"
SHA512="83f7e717b8adc9049e828a27629e7347be2fa0aef6c8404608059410cebaafa0c2659317b615634fbd5d83f9a245bcf1a64e5d2cd0d8e3ec8aeaa3dcf0e51298"

WORK=/work
SRC="$WORK/src"
OUT="$WORK/out"

echo "== toolchain =="
apk add --no-cache \
	bash bc bison build-base ccache \
	clang lld llvm \
	curl dtc elfutils-dev findutils flex kmod linux-headers \
	openssl-dev pahole patch perl python3 tar xz zstd
clang --version | head -1
ld.lld --version | head -1

mkdir -p "$SRC" "$OUT"
cd "$SRC"

if [ ! -f "$TARBALL" ]; then
	echo "== download $TAG =="
	curl -fL --retry 3 --retry-delay 5 -o "$TARBALL" "$URL"
fi
echo "$SHA512  $TARBALL" | sha512sum -c -

echo "== extract =="
tar -xzf "$TARBALL"
BUILD="$SRC/linux-${KVER}-sdm660"
[ -d "$BUILD" ] || BUILD="$(find "$SRC" -maxdepth 1 -type d -name 'linux-*' | head -1)"
echo "builddir: $BUILD"
cd "$BUILD"

echo "== apply patch =="
ls -la "$WORK/patches" "$WORK/config" || true
PATCH="$(find "$WORK/patches" -maxdepth 1 -name '*.patch' | sort | head -1)"
echo "patch: $PATCH"
[ -n "$PATCH" ] || { echo "no patch found" >&2; exit 1; }
patch -p1 --batch --forward < "$PATCH"

echo "== config =="
cp -v "$WORK/config/config-${FLAVOR}.aarch64" .config

echo "== build =="
make -j"$(nproc)" ARCH=arm64 LLVM=1 \
	KBUILD_BUILD_VERSION=1 all Image.gz modules

echo "== install modules =="
make ARCH=arm64 LLVM=1 \
	INSTALL_MOD_PATH="$OUT/modroot" \
	INSTALL_MOD_STRIP=1 \
	modules_install

echo "== install dtbs =="
make ARCH=arm64 LLVM=1 INSTALL_DTBS_PATH="$OUT/dtbs" dtbs_install

echo "== depmod (guard against empty dependency lists) =="
MODDIR="$OUT/modroot/usr/lib/modules/${KVER}-sdm660"
depmod -b "$OUT/modroot" "${KVER}-sdm660"
grep -E 'ath10k_snoc\.ko[^:]*: .*ath10k_core\.ko' "$MODDIR/modules.dep" \
	&& echo "depmod OK" \
	|| { echo "ERROR: modules.dep incomplete (empty deps)" >&2; exit 1; }

echo "== collect =="
cp -v arch/arm64/boot/Image.gz "$OUT/vmlinuz"
cp -v arch/arm64/boot/vmlinuz.efi "$OUT/vmlinuz.efi"
cp -v System.map "$OUT/System.map"

MSM="$OUT/modroot/usr/lib/modules/${KVER}-sdm660/kernel/drivers/gpu/drm/msm/msm.ko.zst"
if [ ! -f "$MSM" ]; then
	MSM="$(find "$OUT/modroot" -name 'msm.ko*' | head -1)"
fi
echo "== msm module =="
ls -l "$MSM"
sha256sum "$MSM"

echo "== version =="
cat include/config/kernel.release
strings "$OUT/vmlinuz" | grep -m1 -E '^7\.0\.14-sdm660' || true

echo "== done =="
du -sh "$OUT"