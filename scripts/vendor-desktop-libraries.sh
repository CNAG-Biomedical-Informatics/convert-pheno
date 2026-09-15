#!/usr/bin/env bash

set -euo pipefail

engine="${1:?Usage: vendor-desktop-libraries.sh ENGINE_DIRECTORY}"
runtime="$engine/runtime"
mkdir -p "$runtime/lib"

case "$(uname -s)" in
  Linux)
    while IFS= read -r binary; do
      while IFS= read -r library; do
        case "$(basename "$library")" in
          libssl.so.*|libcrypto.so.*|libexpat.so.*|libbz2.so.*|libz.so.*)
            cp -L "$library" "$runtime/lib/$(basename "$library")"
            ;;
        esac
      done < <(ldd "$binary" 2>/dev/null | awk '/=> \/.* \(0x/ {print $3}')
    done < <(find "$runtime" -type f \( -name 'perl' -o -name '*.so' \))
    ;;
  Darwin)
    # Resolve Homebrew libraries recursively, then use an executable-relative
    # runpath so the app never depends on the build machine's Homebrew prefix.
    for _pass in 1 2 3 4; do
      copied=0
      while IFS= read -r binary; do
        while IFS= read -r library; do
          case "$library" in
            /opt/homebrew/*|/usr/local/*)
              target="$runtime/lib/$(basename "$library")"
              if [[ ! -f "$target" ]]; then
                cp -L "$library" "$target"
                copied=1
              fi
              ;;
          esac
        done < <(otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}')
      done < <(find "$runtime" -type f \( -name 'perl' -o -name '*.bundle' -o -name '*.dylib' \))
      [[ "$copied" -eq 1 ]] || break
    done
    while IFS= read -r binary; do
      while IFS= read -r library; do
        case "$library" in
          /opt/homebrew/*|/usr/local/*)
            install_name_tool -change "$library" "@rpath/$(basename "$library")" "$binary"
            ;;
        esac
      done < <(otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}')
    done < <(find "$runtime" -type f \( -name 'perl' -o -name '*.bundle' -o -name '*.dylib' \))
    while IFS= read -r library; do
      install_name_tool -id "@rpath/$(basename "$library")" "$library"
    done < <(find "$runtime/lib" -maxdepth 1 -type f -name '*.dylib')
    install_name_tool -add_rpath '@executable_path/../lib' "$runtime/bin/perl" 2>/dev/null || true
    ;;
  *)
    echo "Unsupported runtime platform" >&2
    exit 1
    ;;
esac
