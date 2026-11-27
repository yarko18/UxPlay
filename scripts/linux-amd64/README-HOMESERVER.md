# UxPlay on an AMD64 home server

This package targets Debian Bookworm on `amd64`/`x86_64`. It cannot run on an
ARM64 Raspberry Pi; use the `linux-arm64` package there.

## Install

From the extracted package directory:

```sh
./install.sh
```

For a package update after dependencies are installed:

```sh
./install.sh --no-deps
```

If `apt-get update` is blocked by an unrelated third-party repository and the
Debian package indexes are already current, install from those indexes with:

```sh
./install.sh --no-update
```

Unlike `--no-deps`, this still installs every GStreamer runtime dependency.

## HDMI hot-plug

`uxplay-home` may be started while HDMI/DP is disconnected. It waits for a DRM
connector and valid HDMI audio ELD, then starts UxPlay. If the cable is removed,
the launcher stops only UxPlay, waits for the display to return, and starts it
again with the new EDID. Rebooting the computer is not required.

The launcher can be used directly from the extracted package:

```sh
./uxplay-home --diagnose
./uxplay-home --debug
```

`./install.sh` installs the GStreamer runtime dependencies and copies the same
launcher to `/usr/local/bin/uxplay-home`.

Check the current state without starting the receiver:

```sh
./uxplay-home --diagnose
```

Start the receiver with debug logging:

```sh
./uxplay-home --debug
```

The default video output is `kmssink`; the default audio output is the ALSA
HDMI device selected from `/proc/asound/*/eld*`. Both may be overridden:

```sh
UXPLAY_VIDEO_SINK=glimagesink uxplay-home
UXPLAY_ALSA_DEVICE=plughw:CARD=PCH,DEV=3 uxplay-home
```

Useful controls:

- `UXPLAY_REQUIRE_HDMI_AUDIO=0` allows a display with no HDMI audio ELD.
- `UXPLAY_DISPLAY_POLL_SECONDS=2` changes the hot-plug polling interval.
- `UXPLAY_LOG_FILE=~/uxplay.log` selects the append-only log file.
- `UXPLAY_DECODER=avdec_h264` forces software H.264 decoding.

KMS output requires access to `/dev/dri/card*`; ALSA output requires access to
`/dev/snd/*`. The service user therefore normally belongs to the `video`,
`render`, and `audio` groups. A running desktop compositor may own KMS and must
be accounted for when the final service is configured.
