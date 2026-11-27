#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")" && pwd)"
install_dependencies=true
update_package_lists=true

usage() {
    cat <<EOF
Usage: $0 [--no-update] [--no-deps]

  --no-update  Use the existing APT package indexes.
  --no-deps    Install only UxPlay; do not use APT.
EOF
}

while (($#)); do
    case "$1" in
        --no-update)
            update_package_lists=false
            ;;
        --no-deps)
            install_dependencies=false
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if command -v dpkg >/dev/null 2>&1; then
    architecture="$(dpkg --print-architecture)"
    if [[ "$architecture" != "amd64" ]]; then
        echo "This package requires Debian AMD64 (detected: $architecture)." >&2
        exit 1
    fi
fi

if [[ "$install_dependencies" == true ]]; then
    if [[ "$update_package_lists" == true ]] && ! sudo apt-get update; then
        cat >&2 <<'EOF'

APT package-list update failed. Fix the failing repository, or use
--no-update when the Debian package indexes are already current:

  ./install.sh --no-update
EOF
        exit 1
    fi
    sudo apt-get install -y \
        gstreamer1.0-alsa \
        gstreamer1.0-gl \
        gstreamer1.0-libav \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-tools \
        gstreamer1.0-vaapi \
        intel-media-va-driver \
        libgstreamer1.0-0 \
        libssl3
fi

sudo install -d -m 0755 /usr/local/lib/uxplay
sudo install -m 0644 \
    "$package_dir/lib/uxplay/libplist-2.0.so.3" \
    /usr/local/lib/uxplay/libplist-2.0.so.3
sudo install -m 0755 "$package_dir/bin/uxplay" /usr/local/bin/uxplay
sudo install -m 0755 "$package_dir/uxplay-home" /usr/local/bin/uxplay-home

if ldd /usr/local/bin/uxplay | grep -q 'not found'; then
    echo "UxPlay still has unresolved shared-library dependencies:" >&2
    ldd /usr/local/bin/uxplay >&2
    exit 1
fi

echo "Installed /usr/local/bin/uxplay"
echo "Installed /usr/local/bin/uxplay-home"
echo "The launcher waits for HDMI/DP hot-plug; no computer restart is needed."
echo "Inspect without starting UxPlay: uxplay-home --diagnose"
echo "Run with protocol logging:       uxplay-home --debug"
