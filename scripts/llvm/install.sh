#!/usr/bin/env bash
# llvm installer (uses apt.llvm.org's llvm.sh).
# https://apt.llvm.org/
set -e

LLVM_VERSION="${LLVM_VERSION:-22}"
LLVM_ALL="${ALL:-true}"

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
