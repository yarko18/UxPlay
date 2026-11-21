# Fork changelog

## 1.74.7

- Added low-latency mirroring with a bounded decoded-frame queue.
- Improved direct HLS playback: fast single-variant startup, correct portrait
  quality limits, and sender-selected audio language.
- Added reproducible Linux ARM64 cross-build and Raspberry Pi packaging.
- Added `uxplay-home` for Raspberry Pi OS Lite/KMS with HDMI and decoder
  diagnostics, automatic quality selection, hardware H.264, HDMI audio, and
  bounded per-run logging.
