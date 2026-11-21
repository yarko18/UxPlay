#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")" && pwd)"
install_dependencies=true

if [[ "${1:-}" == "--no-deps" ]]; then
    install_dependencies=false
elif [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--no-deps]" >&2
    exit 2
fi

if command -v dpkg >/dev/null 2>&1; then
    architecture="$(dpkg --print-architecture)"
    if [[ "$architecture" != "arm64" ]]; then
        echo "This package requires a 64-bit ARM OS (dpkg architecture: arm64)." >&2
        echo "Detected: $architecture" >&2
        exit 1
    fi
fi

if [[ "$install_dependencies" == true ]]; then
    sudo apt-get update
    sudo apt-get install -y \
        libssl-dev \
        libplist-dev \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        gstreamer1.0-tools \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-libav \
        gstreamer1.0-gl \
        gstreamer1.0-alsa \
        gstreamer1.0-x
    sudo apt-get install -y kms++-utils
fi

sudo install -d -m 0755 /usr/local/lib/uxplay
sudo install -m 0644 \
    "$package_dir/lib/uxplay/libplist-2.0.so.3" \
    /usr/local/lib/uxplay/libplist-2.0.so.3
sudo install -m 0755 "$package_dir/bin/uxplay" /usr/local/bin/uxplay
sudo install -m 0755 "$package_dir/run_raspberry_home.sh" /usr/local/bin/uxplay-home

wireplumber_dir="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber/wireplumber.conf.d"
install -d -m 0755 "$wireplumber_dir"
install -m 0644 \
    "$package_dir/51-hdmi-audio.conf" \
    "$wireplumber_dir/51-hdmi-audio.conf"

if systemctl --user --quiet is-active wireplumber.service; then
    systemctl --user restart wireplumber.service
    sleep 2
    pactl set-card-profile alsa_card.platform-3f902000.hdmi output:hdmi-stereo
    pactl set-default-sink alsa_output.platform-3f902000.hdmi.hdmi-stereo
    pactl set-sink-mute @DEFAULT_SINK@ false
    pactl set-sink-volume @DEFAULT_SINK@ 100%
fi

if ldd /usr/local/bin/uxplay | grep -q 'not found'; then
    echo "UxPlay still has unresolved shared-library dependencies:" >&2
    ldd /usr/local/bin/uxplay >&2
    exit 1
fi

echo "Installed /usr/local/bin/uxplay"
echo "Installed /usr/local/bin/uxplay-home"
echo "Configured global Raspberry Pi audio output: HDMI"
echo "Test the TV output first:"
echo "  gst-launch-1.0 videotestsrc ! autovideosink"
echo "Then run: uxplay-home"
echo "Debug log level: uxplay-home --debug (or: uxplay-home -g)"
echo "HDMI/decoder diagnostics only: uxplay-home --diagnose"
echo "The fresh log path is printed when the launcher starts."
