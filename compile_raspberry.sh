#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
image="${UXPLAY_BUILD_IMAGE:-uxplay-linux-arm64-build}"
fork_revision="${UXPLAY_FORK_REVISION:-7}"

if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
    engine="$CONTAINER_ENGINE"
elif command -v podman >/dev/null 2>&1; then
    engine="podman"
elif command -v docker >/dev/null 2>&1; then
    engine="docker"
else
    echo "Podman or Docker is required for the ARM64 cross-build." >&2
    exit 1
fi

version="$(sed -n 's/^#define VERSION "\([^"]*\)"/\1/p' "$repo/uxplay.cpp" | head -n 1)"
if [[ -z "$version" ]]; then
    echo "Cannot read the UxPlay version from uxplay.cpp." >&2
    exit 1
fi

package_version="${version}.${fork_revision}"

echo "Building UxPlay ${package_version} for Linux ARM64 with ${engine}"
"$engine" build \
    --tag "$image" \
    --file "$repo/scripts/linux-arm64/Containerfile" \
    "$repo/scripts/linux-arm64"

run_args=(run --rm)
if [[ "$engine" == "podman" ]]; then
    run_args+=(--userns=keep-id)
else
    run_args+=(--user "$(id -u):$(id -g)")
fi

"$engine" "${run_args[@]}" \
    --mount "type=bind,src=$repo,target=/src" \
    --env "UXPLAY_FORK_REVISION=$fork_revision" \
    --workdir /src \
    "$image" \
    bash /src/scripts/linux-arm64/build.sh

echo "ARM64 package:"
ls -lh "$repo/dist/uxplay-${package_version}-linux-arm64.tar.gz"
