#!/usr/bin/env bash
# llvm feature installer (uses apt.llvm.org's llvm.sh).
# https://apt.llvm.org/
set -e

LLVM_VERSION="${VERSION:-22}"
LLVM_ALL="${ALL:-true}"

# llvm.sh writes the LLVM apt source in deb822 format on trixie/forky/sid, so
# software-properties-common (gone from trixie) is no longer required. Older
# Debian/Ubuntu suites still need add-apt-repository — install it on demand
# when llvm.sh asks for it. Only install what's missing.
NEED=()
for pkg in ca-certificates curl gnupg lsb-release wget; do
  dpkg -s "$pkg" >/dev/null 2>&1 || NEED+=("$pkg")
done
if [ "${#NEED[@]}" -gt 0 ]; then
  apt-get update
  apt-get install -y --no-install-recommends "${NEED[@]}"
  rm -rf /var/lib/apt/lists/*
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

curl -fsSL -o "$TMPDIR/llvm.sh" https://apt.llvm.org/llvm.sh
chmod +x "$TMPDIR/llvm.sh"

EXTRA_ARGS=()
if [ "$LLVM_ALL" = "true" ]; then
  EXTRA_ARGS+=("all")
fi

"$TMPDIR/llvm.sh" "$LLVM_VERSION" "${EXTRA_ARGS[@]}"

# Symlink versioned binaries to unsuffixed names so generic tooling finds them.
for bin in \
    clang clang++ clang-cpp \
    clang-format clang-tidy clangd \
    lld ld.lld lld-link \
    lldb lldb-server \
    llvm-config llvm-symbolizer llvm-ar llvm-nm llvm-objdump llvm-objcopy \
    llvm-ranlib llvm-readelf llvm-strip llvm-cov llvm-profdata; do
  if [ -x "/usr/bin/${bin}-${LLVM_VERSION}" ]; then
    ln -sf "/usr/bin/${bin}-${LLVM_VERSION}" "/usr/local/bin/${bin}"
  fi
done
