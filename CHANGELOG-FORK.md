# Fork changelog

## 1.74.7

- Added low-latency mirroring with a bounded decoded-frame queue.
- Improved direct HLS playback: fast single-variant startup, correct portrait
  quality limits, and sender-selected audio language.
- Added reproducible Linux ARM64 cross-build and Raspberry Pi packaging.
- Added `compile_linux.sh --arch arm64|amd64`, native AMD64 packaging, and a
  home-server launcher that waits for HDMI/DP audio hot-plug without requiring
  a computer restart.
- Fixed HDMI ELD-to-PCM selection and made direct HLS playback honor the
  configured UxPlay audio sink instead of silently falling back to PulseAudio.
- Prevented direct HLS playback from opening a second, exclusive ALSA pipeline
  when Safari also advertises the same soundtrack as an AirPlay ALAC stream.
- Added `uxplay-home` for Raspberry Pi OS Lite/KMS with HDMI and decoder
  diagnostics, automatic quality selection, hardware H.264, HDMI audio, and
  bounded per-run logging.
