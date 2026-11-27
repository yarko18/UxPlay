#!/usr/bin/env bash
set -euo pipefail

repo="/src"
version="$(sed -n 's/^#define VERSION "\([^"]*\)"/\1/p' "$repo/uxplay.cpp" | head -n 1)"
fork_revision="${UXPLAY_FORK_REVISION:-1}"
package_version="${version}.${fork_revision}"
target_arch="amd64"
build_dir="$repo/build/linux-$target_arch"
stage_dir="$repo/build/stage-linux-$target_arch"
package_name="uxplay-${package_version}-linux-${target_arch}"
package_dir="$repo/build/$package_name"
archive="$repo/dist/$package_name.tar.gz"

rm -rf "$build_dir" "$stage_dir" "$package_dir"
mkdir -p \
    "$build_dir" \
    "$stage_dir" \
    "$package_dir/bin" \
    "$package_dir/lib/uxplay" \
    "$repo/dist"

cmake \
    -S "$repo" \
    -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib/uxplay' \
    -DNO_MARCH_NATIVE=ON \
    -DNO_X11_DEPS=ON

cmake --build "$build_dir" --parallel "$(nproc)"
DESTDIR="$stage_dir" cmake --install "$build_dir"

binary="$stage_dir/usr/bin/uxplay"
if ! file "$binary" | grep -Eq 'x86-64|x86_64'; then
    echo "The result is not an AMD64 binary:" >&2
    file "$binary" >&2
    exit 1
fi

if ! readelf -d "$binary" | grep -Fq '$ORIGIN/../lib/uxplay'; then
    echo "The AMD64 binary does not contain the bundled-library RPATH." >&2
    readelf -d "$binary" >&2
    exit 1
fi

plist_runtime="/usr/lib/x86_64-linux-gnu/libplist-2.0.so.3"
if [[ ! -e "$plist_runtime" ]]; then
    echo "Cannot find the Bookworm AMD64 libplist runtime: $plist_runtime" >&2
    exit 1
fi

cp "$binary" "$package_dir/bin/uxplay"
cp -L "$plist_runtime" "$package_dir/lib/uxplay/libplist-2.0.so.3"
cp "$repo/LICENSE" "$package_dir/LICENSE"
cp "$repo/scripts/linux-amd64/README-HOMESERVER.md" \
    "$package_dir/README-HOMESERVER.md"
cp "$repo/scripts/linux-amd64/install.sh" "$package_dir/install.sh"
cp "$repo/uxplay-home" "$package_dir/uxplay-home"
chmod 0755 \
    "$package_dir/bin/uxplay" \
    "$package_dir/install.sh" \
    "$package_dir/uxplay-home"
chmod 0644 "$package_dir/lib/uxplay/libplist-2.0.so.3"

tar -C "$repo/build" -czf "$archive" "$package_name"

file "$binary"
echo "Created $archive"
