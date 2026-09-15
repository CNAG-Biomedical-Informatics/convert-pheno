#!/usr/bin/env bash

set -euo pipefail

prefix="${1:?Usage: build-relocatable-perl.sh PREFIX}"
version=5.42.3
sha256=1137740985837b5cdf15f0cfab932279dcb4352f912fed6fc144e8b4f0823627
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

archive="$work/perl-$version.tar.gz"
curl --fail --location --retry 4 \
  "https://www.cpan.org/src/5.0/perl-$version.tar.gz" \
  --output "$archive"
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
test "$actual" = "$sha256"

tar -xzf "$archive" -C "$work"
cd "$work/perl-$version"
./Configure -des \
  -Dprefix="$prefix" \
  -Duserelocatableinc \
  -Duse64bitall
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
make install

curl --fail --location --retry 4 https://cpanmin.us --output "$work/cpanm"
"$prefix/bin/perl" "$work/cpanm" --notest App::cpanminus
"$prefix/bin/perl" -MConfig -e \
  'die "Perl was not built with relocatable library paths\n" unless $Config{userelocatableinc}'
