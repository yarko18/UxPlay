# UxPlay on a Raspberry Pi connected to a TV

This package is for a 64-bit Raspberry Pi OS (`dpkg --print-architecture`
must print `arm64`). It was cross-built against Debian Bookworm, so it can run
on Raspberry Pi OS Bookworm or a newer compatible release.

## Install

From the extracted package directory:

```sh
./install.sh
```

For a later package update, when the dependencies are already installed:

```sh
./install.sh --no-deps
```

The installer places the executable at `/usr/local/bin/uxplay` and installs
the GStreamer runtime plugins used for AirPlay audio, mirroring, H.264 and HLS.
It also installs the tested TV launcher as `/usr/local/bin/uxplay-home`.
The compatible Bookworm `libplist-2.0.so.3` is bundled privately under
`/usr/local/lib/uxplay`, so it can coexist with a newer system libplist.

## Test the display

Run this locally on the Raspberry Pi desktop:

```sh
gst-launch-1.0 videotestsrc ! autovideosink
```

If the test picture is not visible, test a specific TV output:

```sh
gst-launch-1.0 videotestsrc ! waylandsink
gst-launch-1.0 videotestsrc ! glimagesink
```

On Raspberry Pi OS Lite, outside a desktop session:

```sh
gst-launch-1.0 videotestsrc ! kmssink
```

## Run UxPlay

For the tested Raspberry Pi OS Lite/KMS configuration, run:

```sh
uxplay-home
```

At every start, the launcher reads the connected display's EDID/KMS modes,
the currently active HDMI mode, and the GStreamer H.264 decoder. It prints a
240p/360p/480p/720p/1080p availability table for 30 and 60 fps and restricts
AirPlay to the highest mode supported by both HDMI and the decoder. Run only
the check without starting the receiver with:

```sh
uxplay-home --diagnose
```

The EDID result describes the complete HDMI path (port, cable and display).
A cable cannot be queried separately, so a marginal cable may still fail at a
mode that the display advertises. Raspberry Pi 3 marks 1080p60 as experimental
but leaves it enabled when HDMI advertises it.

The package installer configures HDMI as the global PipeWire output, disables
the legacy analogue jack in WirePlumber, unmutes HDMI and sets its initial
volume to 100%. The rule is stored in
`~/.config/wireplumber/wireplumber.conf.d/51-hdmi-audio.conf` and survives a
reboot.

It uses the hardware H.264 decoder, keeps the best eligible HLS variant,
avoids the unstable V4L2 converter, enables the low-latency decoded-frame
queue and advertises 60 fps. The launcher prints a short status summary in the
terminal and writes UxPlay output to `uxplay.log`. The file is truncated on
every start. In a writable package directory it is kept beside the launcher;
the installed `/usr/local/bin/uxplay-home` command uses the current directory.

YouTube HLS audio follows the track selected in the sender app. The receiver
keeps the audio rendition marked `DEFAULT=YES` in the playlist instead of
replacing it with the Raspberry Pi system locale. An explicit UxPlay
`-lang xx` argument still overrides the sender selection when desired.

Additional UxPlay arguments may be appended to the command. To choose another
log path:

```sh
UXPLAY_LOG_FILE=~/my-uxplay.log uxplay-home
```

For protocol diagnostics, use either `uxplay-home --debug` or `uxplay-home -g`.
Both select UxPlay's `-d 1` level: debug messages are logged, while packet
payload dumps are suppressed. `UXPLAY_DEBUG=1 uxplay-home` remains supported.

Raspberry Pi OS Desktop with Wayland:

```sh
uxplay -n "Raspberry Video" -nh -hls -fs -vs waylandsink
```

If `waylandsink` does not work, omit `-vs waylandsink` to let GStreamer choose,
or try `-vs glimagesink`.

Raspberry Pi OS Lite/KMS console:

```sh
uxplay -n "Raspberry Video" -nh -hls -fs -vs kmssink
```

The user running UxPlay must have access to the `video`, `render`, and `audio`
groups for KMS output. If necessary:

```sh
sudo usermod -aG video,render,audio "$USER"
```

Log out and back in after changing groups.

`-hls` enables direct YouTube AirPlay video. Screen mirroring and Photos video
use the normal AirPlay mirroring path. UxPlay 1.74 currently describes direct
HLS support as YouTube-only; arbitrary browser video and DRM-protected video
are not guaranteed to work.

For a Pi 4 or older using the hardware H.264 decoder, add `-bt709` if colors
are wrong. A Pi 5 uses software H.264 decoding; if automatic decoder selection
fails, add `-avdec`.

Stop UxPlay with `Ctrl+C`.
