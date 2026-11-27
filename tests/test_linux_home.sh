#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/uxplay-linux-home-test.XXXXXX)"
launcher_pid=""

cleanup() {
    if [[ -n "$launcher_pid" ]] && kill -0 "$launcher_pid" 2>/dev/null; then
        kill -TERM "$launcher_pid" 2>/dev/null || true
        wait "$launcher_pid" 2>/dev/null || true
    fi
    rm -rf -- "$test_root"
}
trap cleanup EXIT

mkdir -p \
    "$test_root/package/bin" \
    "$test_root/tools" \
    "$test_root/drm/card0-HDMI-A-1" \
    "$test_root/dri" \
    "$test_root/asound/card0/pcm3p/sub0"
cp "$repo/uxplay-home" "$test_root/package/uxplay-home"

cat >"$test_root/package/bin/uxplay" <<'EOF'
#!/usr/bin/env bash
echo start >>"$UXPLAY_FAKE_STARTS"
trap 'exit 0' TERM INT HUP
while true; do sleep 1; done
EOF
chmod 0755 "$test_root/package/bin/uxplay"

cat >"$test_root/tools/gst-inspect-1.0" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    avdec_h264|kmssink|alsasink) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod 0755 "$test_root/tools/gst-inspect-1.0"

printf 'connected\n' >"$test_root/drm/card0-HDMI-A-1/status"
printf '1920x1080\n1280x720\n' >"$test_root/drm/card0-HDMI-A-1/modes"
printf 'fake DRM device\n' >"$test_root/dri/card0"
printf 'PCH\n' >"$test_root/asound/card0/id"
cat >"$test_root/asound/card0/eld#2.3" <<'EOF'
monitor_present         1
eld_valid               1
monitor_name            Test TV
codec_pin_nid           0x5
EOF
printf 'state: closed\n' >"$test_root/asound/card0/pcm3p/sub0/status"

common_env=(
    PATH="$test_root/tools:$PATH"
    UXPLAY_DRM_ROOT="$test_root/drm"
    UXPLAY_DRI_ROOT="$test_root/dri"
    UXPLAY_ASOUND_ROOT="$test_root/asound"
    UXPLAY_DISPLAY_POLL_SECONDS=1
    UXPLAY_FAKE_STARTS="$test_root/starts"
    UXPLAY_LOG_FILE="$test_root/uxplay.log"
)

env "${common_env[@]}" \
    "$test_root/package/uxplay-home" --diagnose \
    >"$test_root/diagnose.out"
grep -q 'DRM display:  HDMI-A-1' "$test_root/diagnose.out"
grep -q 'ALSA output: plughw:CARD=PCH,DEV=3' "$test_root/diagnose.out"
grep -q 'Status:       ready' "$test_root/diagnose.out"

env "${common_env[@]}" \
    "$test_root/package/uxplay-home" \
    >"$test_root/launcher.out" 2>&1 &
launcher_pid=$!

for _ in {1..10}; do
    [[ -r "$test_root/starts" ]] && \
        [[ "$(grep -c '^start$' "$test_root/starts")" -ge 1 ]] && break
    sleep 1
done
[[ "$(grep -c '^start$' "$test_root/starts")" -eq 1 ]]

printf 'disconnected\n' >"$test_root/drm/card0-HDMI-A-1/status"
for _ in {1..10}; do
    grep -q 'Display disconnected' "$test_root/launcher.out" && break
    sleep 1
done
grep -q 'Display disconnected' "$test_root/launcher.out"

printf 'connected\n' >"$test_root/drm/card0-HDMI-A-1/status"
for _ in {1..10}; do
    [[ "$(grep -c '^start$' "$test_root/starts")" -ge 2 ]] && break
    sleep 1
done
[[ "$(grep -c '^start$' "$test_root/starts")" -eq 2 ]]

kill -TERM "$launcher_pid"
wait "$launcher_pid" 2>/dev/null || true
launcher_pid=""

echo "linux home launcher hot-plug test: PASS"
