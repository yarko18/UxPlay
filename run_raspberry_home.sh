#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -x "$script_dir/bin/uxplay" ]]; then
    uxplay_bin="$script_dir/bin/uxplay"
elif command -v uxplay >/dev/null 2>&1; then
    uxplay_bin="$(command -v uxplay)"
else
    echo "UxPlay binary not found in $script_dir/bin or PATH" >&2
    exit 127
fi

# A packaged launcher keeps its log beside this script. /usr/local/bin is
# normally not writable, so the installed uxplay-home command falls back to
# the directory from which it was started. UXPLAY_LOG_FILE overrides both.
if [[ -w "$script_dir" ]]; then
    default_log="$script_dir/uxplay.log"
else
    default_log="$PWD/uxplay.log"
fi
log_file="${UXPLAY_LOG_FILE:-$default_log}"

video_levels=(240 360 480 720 1080)

video_width_for_height() {
    case "$1" in
        240) echo 426 ;;
        360) echo 640 ;;
        480) echo 854 ;;
        720) echo 1280 ;;
        1080) echo 1920 ;;
        *) return 1 ;;
    esac
}

highest_video_level() {
    local limit="$1"
    local selected=0
    local level
    for level in "${video_levels[@]}"; do
        if ((level <= limit)); then
            selected="$level"
        fi
    done
    echo "$selected"
}

min_int() {
    if (($1 < $2)); then
        echo "$1"
    else
        echo "$2"
    fi
}

pi_model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)"
hdmi_connector=""
for connector in /sys/class/drm/card*-HDMI-A-*; do
    [[ -e "$connector" ]] || continue
    if [[ "$(<"$connector/status")" == "connected" ]]; then
        hdmi_connector="$connector"
        break
    fi
done

display_name="disconnected"
display_max_width=0
display_max_height=0
display_max_fps=0
display_max_pixels=0
display_max_short_side=0
display_60_short_side=0
active_width=0
active_height=0
active_fps=0

if [[ -n "$hdmi_connector" ]]; then
    display_name="$(basename "$hdmi_connector")"
    display_name="${display_name#card*-}"
fi

if command -v kmsprint >/dev/null 2>&1 && [[ -n "$hdmi_connector" ]]; then
    while IFS= read -r mode_line; do
        # Interlaced modes contain "i@" and intentionally do not match.
        if [[ "$mode_line" =~ ^[[:space:]]*[0-9]+[[:space:]]+([0-9]+)x([0-9]+)@([0-9]+([.][0-9]+)?) ]]; then
            mode_width="${BASH_REMATCH[1]}"
            mode_height="${BASH_REMATCH[2]}"
            mode_fps="$(awk -v fps="${BASH_REMATCH[3]}" 'BEGIN { printf "%.0f", fps }')"
            mode_pixels=$((mode_width * mode_height))
            mode_short_side="$(min_int "$mode_width" "$mode_height")"
            if ((mode_pixels > display_max_pixels ||
                 (mode_pixels == display_max_pixels && mode_fps > display_max_fps))); then
                display_max_width="$mode_width"
                display_max_height="$mode_height"
                display_max_fps="$mode_fps"
                display_max_pixels="$mode_pixels"
            fi
            if ((mode_short_side > display_max_short_side)); then
                display_max_short_side="$mode_short_side"
            fi
            if ((mode_fps >= 59 && mode_short_side > display_60_short_side)); then
                display_60_short_side="$mode_short_side"
            fi
        fi
    done < <(kmsprint -m 2>/dev/null)

    while IFS= read -r active_line; do
        if [[ "$active_line" =~ Crtc.*[[:space:]]([0-9]+)x([0-9]+)@([0-9]+([.][0-9]+)?) ]]; then
            active_width="${BASH_REMATCH[1]}"
            active_height="${BASH_REMATCH[2]}"
            active_fps="$(awk -v fps="${BASH_REMATCH[3]}" 'BEGIN { printf "%.0f", fps }')"
            break
        fi
    done < <(kmsprint 2>/dev/null)
fi

# Fallback for systems without kmsprint: sysfs exposes resolutions, but not
# their refresh rates. In that case advertise 30 fps conservatively.
if ((display_max_pixels == 0)) && [[ -n "$hdmi_connector" ]]; then
    while IFS= read -r mode; do
        if [[ "$mode" =~ ^([0-9]+)x([0-9]+)$ ]]; then
            mode_width="${BASH_REMATCH[1]}"
            mode_height="${BASH_REMATCH[2]}"
            mode_pixels=$((mode_width * mode_height))
            mode_short_side="$(min_int "$mode_width" "$mode_height")"
            if ((mode_pixels > display_max_pixels)); then
                display_max_width="$mode_width"
                display_max_height="$mode_height"
                display_max_pixels="$mode_pixels"
                display_max_fps=30
            fi
            if ((mode_short_side > display_max_short_side)); then
                display_max_short_side="$mode_short_side"
            fi
        fi
    done <"$hdmi_connector/modes"
fi

hardware_h264=false
if command -v gst-inspect-1.0 >/dev/null 2>&1 &&
   gst-inspect-1.0 v4l2h264dec >/dev/null 2>&1; then
    hardware_h264=true
fi

# Raspberry Pi's H.264 path is limited to 1080p. HDMI/EDID can lower this.
decoder_max_short_side=1080
display_level_30="$(highest_video_level "$display_max_short_side")"
display_level_60="$(highest_video_level "$display_60_short_side")"
decoder_level="$(highest_video_level "$decoder_max_short_side")"
hls_max_30="$(min_int "$display_level_30" "$decoder_level")"
hls_max_60="$(min_int "$display_level_60" "$decoder_level")"

if [[ "$hardware_h264" != true ]]; then
    hls_max_30=0
    hls_max_60=0
fi

availability_for() {
    local level="$1"
    local fps="$2"
    local display_limit="$display_level_30"
    if ((fps == 60)); then
        display_limit="$display_level_60"
    fi
    if ((level > display_limit)); then
        printf 'no (HDMI)'
    elif [[ "$hardware_h264" != true ]] || ((level > decoder_level)); then
        printf 'no (decoder)'
    elif [[ "$pi_model" == *"Raspberry Pi 3"* ]] &&
         ((level == 1080 && fps == 60)); then
        printf 'yes (experimental)'
    else
        printf 'yes'
    fi
}

print_capabilities() {
    local level
    printf '  Hardware:  %s\n' "$pi_model"
    printf '  HDMI:      %s\n' "$display_name"
    if ((display_max_pixels > 0)); then
        printf '  EDID max:  %dx%d @ %d Hz progressive\n' \
            "$display_max_width" "$display_max_height" "$display_max_fps"
    else
        printf '  EDID max:  unavailable\n'
    fi
    if ((active_width > 0)); then
        printf '  Active:    %dx%d @ %d Hz\n' \
            "$active_width" "$active_height" "$active_fps"
    else
        printf '  Active:    unavailable\n'
    fi
    printf '  H.264:     %s\n' \
        "$([[ "$hardware_h264" == true ]] && echo 'v4l2h264dec hardware decoder' || echo 'hardware decoder unavailable')"
    printf '\n'
    printf '  AirPlay H.264 source availability\n'
    printf '  %-9s %-20s %-20s\n' 'Quality' 'up to 30 fps' 'up to 60 fps'
    for level in "${video_levels[@]}"; do
        printf '  %-9s %-20s %-20s\n' \
            "${level}p" "$(availability_for "$level" 30)" "$(availability_for "$level" 60)"
    done
    printf '\n'
}

debug=false
diagnose_only=false
if [[ "${UXPLAY_DEBUG:-0}" == "1" ]]; then
    debug=true
fi

forward_args=()
while (($#)); do
    case "$1" in
        --debug|-g)
            debug=true
            ;;
        --diagnose|--check)
            diagnose_only=true
            ;;
        --)
            shift
            forward_args+=("$@")
            break
            ;;
        *)
            forward_args+=("$1")
            ;;
    esac
    shift
done

if ((hls_max_30 == 0)); then
    printf 'UxPlay Home cannot start: no compatible connected HDMI display '
    printf 'or hardware H.264 decoder.\n\n'
    print_capabilities
    exit 1
fi

if ((hls_max_60 == hls_max_30)); then
    hls_profile="AVC:${hls_max_30};HEVC:0;VP9:0;AV1:0"
else
    hls_profile="AVC:${hls_max_30},${hls_max_60};HEVC:0;VP9:0;AV1:0"
fi

mirror_width="$(video_width_for_height "$hls_max_30")"
mirror_fps=30
if ((hls_max_60 >= hls_max_30)); then
    mirror_fps=60
fi

uxplay_args=(
    -n "Raspberry Video" -nh
    -hls -hls-single
    -custom "$hls_profile"
    -s "${mirror_width}x${hls_max_30}"
    -v4l2 -vc identity
    -bt709 -srgb no
    -vsync no -low-latency -fps "$mirror_fps"
    -vs kmssink
)

if [[ "$debug" == true ]]; then
    # UxPlay calls its debug option -d. Value 1 keeps debug messages while
    # suppressing packet payload dumps, which would make the log grow rapidly.
    uxplay_args=(-d 1 "${uxplay_args[@]}")
    log_level="debug (-d 1, packet payloads suppressed)"
else
    log_level="info"
fi

if [[ "$diagnose_only" == true ]]; then
    printf '\nUxPlay Home — HDMI and decoder diagnostics\n'
    print_capabilities
    printf '  Selected HLS profile: %s\n' "$hls_profile"
    printf '  Selected mirroring:   %sx%s @ %s fps\n\n' \
        "$mirror_width" "$hls_max_30" "$mirror_fps"
    exit 0
fi

if ! : >"$log_file"; then
    echo "Cannot create UxPlay log: $log_file" >&2
    exit 1
fi

{
    printf 'UxPlay home receiver started: %s\n' "$(date --iso-8601=seconds)"
    printf 'Binary: %s\n' "$uxplay_bin"
    printf 'Log level: %s\n\n' "$log_level"
} >>"$log_file"

printf '\n'
printf 'UxPlay Home — AirPlay receiver\n'
printf '  Device:    Raspberry Video\n'
print_capabilities
printf '  HLS max:   %sp30 / %sp60\n' "$hls_max_30" "$hls_max_60"
printf '  Profile:   %s\n' "$hls_profile"
printf '  Mirroring: %sx%s @ %s fps, low latency\n' \
    "$mirror_width" "$hls_max_30" "$mirror_fps"
printf '  HLS audio: language selected in the sender app\n'
printf '  Log level: %s\n' "$log_level"
printf '  Log file:  %s (overwritten on every start)\n' "$log_file"
printf '  Status:    waiting for AirPlay connections\n'
printf '  Stop:      Ctrl+C\n'
printf '\n'

set +e
"$uxplay_bin" "${uxplay_args[@]}" "${forward_args[@]}" >>"$log_file" 2>&1
uxplay_status=$?
set -e

case "$uxplay_status" in
    0|130|143)
        printf 'UxPlay stopped (status %d). Log: %s\n' "$uxplay_status" "$log_file"
        ;;
    *)
        printf 'UxPlay exited with status %d. Check: %s\n' \
            "$uxplay_status" "$log_file" >&2
        ;;
esac

exit "$uxplay_status"
