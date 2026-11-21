#!/usr/bin/env bash
set -euo pipefail

repo="/src"
version="$(sed -n 's/^#define VERSION "\([^"]*\)"/\1/p' "$repo/uxplay.cpp" | head -n 1)"
fork_revision="${UXPLAY_FORK_REVISION:-1}"
package_version="${version}.${fork_revision}"
build_dir="$repo/build/linux-arm64"
stage_dir="$repo/build/stage-linux-arm64"
package_name="uxplay-${package_version}-linux-arm64"
package_dir="$repo/build/$package_name"
archive="$repo/dist/$package_name.tar.gz"

rm -rf "$build_dir" "$stage_dir" "$package_dir"
mkdir -p "$build_dir" "$stage_dir" "$package_dir/bin" "$package_dir/lib/uxplay" "$repo/dist"

cmake \
    -S "$repo" \
    -B "$build_dir" \
    -DCMAKE_TOOLCHAIN_FILE="$repo/scripts/linux-arm64/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib/uxplay' \
    -DNO_MARCH_NATIVE=ON \
    -DNO_X11_DEPS=ON \
    -DOPENSSL_INCLUDE_DIR=/usr/include \
    -DOPENSSL_CRYPTO_LIBRARY=/usr/lib/aarch64-linux-gnu/libcrypto.so \
    -DOPENSSL_SSL_LIBRARY=/usr/lib/aarch64-linux-gnu/libssl.so \
    -DLIBPLIST=/usr/lib/aarch64-linux-gnu/libplist-2.0.so

cmake --build "$build_dir" --parallel "$(nproc)"
DESTDIR="$stage_dir" cmake --install "$build_dir"

binary="$stage_dir/usr/bin/uxplay"
if ! file "$binary" | grep -q 'ARM aarch64'; then
    echo "The result is not an ARM64 binary:" >&2
    file "$binary" >&2
    exit 1
fi

if aarch64-linux-gnu-readelf -d "$binary" | grep -q 'x86_64'; then
    echo "The ARM64 binary unexpectedly references an x86_64 object." >&2
    exit 1
fi

if ! aarch64-linux-gnu-readelf -d "$binary" | grep -Fq '$ORIGIN/../lib/uxplay'; then
    echo "The ARM64 binary does not contain the bundled-library RPATH." >&2
    aarch64-linux-gnu-readelf -d "$binary" >&2
    exit 1
fi

plist_runtime="/usr/lib/aarch64-linux-gnu/libplist-2.0.so.3"
if [[ ! -e "$plist_runtime" ]]; then
    echo "Cannot find the Bookworm ARM64 libplist runtime: $plist_runtime" >&2
    exit 1
fi

cp "$binary" "$package_dir/bin/uxplay"
cp -L "$plist_runtime" "$package_dir/lib/uxplay/libplist-2.0.so.3"
cp "$repo/LICENSE" "$package_dir/LICENSE"
cp "$repo/scripts/raspberry/README-RASPBERRY.md" "$package_dir/README-RASPBERRY.md"
cp "$repo/scripts/raspberry/install.sh" "$package_dir/install.sh"
cp "$repo/scripts/raspberry/51-hdmi-audio.conf" "$package_dir/51-hdmi-audio.conf"
cp "$repo/run_raspberry_home.sh" "$package_dir/run_raspberry_home.sh"
chmod 0755 "$package_dir/bin/uxplay" "$package_dir/install.sh" "$package_dir/run_raspberry_home.sh"
chmod 0644 "$package_dir/lib/uxplay/libplist-2.0.so.3" "$package_dir/51-hdmi-audio.conf"

tar -C "$repo/build" -czf "$archive" "$package_name"

file "$binary"
echo "Created $archive"
