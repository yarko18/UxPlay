#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./compile_linux.sh --arch <arm64|amd64>

Build a Debian Bookworm UxPlay package in Podman or Docker.

Accepted architecture aliases:
  arm64, aarch64
  amd64, x86_64

Environment overrides:
  CONTAINER_ENGINE       podman or docker
  UXPLAY_BUILD_IMAGE     container image name
  UXPLAY_FORK_REVISION   package revision (default: 7)
EOF
}

repo="$(cd "$(dirname "$0")" && pwd)"
target_arch=""

while (($#)); do
    case "$1" in
        --arch)
            if (($# < 2)); then
                echo "--arch requires a value." >&2
                usage >&2
                exit 2
            fi
            target_arch="$2"
            shift 2
            ;;
        --arch=*)
            target_arch="${1#*=}"
            shift
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
done

case "$target_arch" in
    arm64|aarch64)
        target_arch="arm64"
        ;;
    amd64|x86_64)
        target_arch="amd64"
        ;;
    "")
        echo "The target architecture is required." >&2
        usage >&2
        exit 2
        ;;
    *)
        echo "Unsupported architecture: $target_arch" >&2
        usage >&2
        exit 2
        ;;
esac

target_dir="$repo/scripts/linux-$target_arch"
if [[ ! -f "$target_dir/Containerfile" || ! -x "$target_dir/build.sh" ]]; then
    echo "The $target_arch build definition is incomplete: $target_dir" >&2
    exit 1
fi

if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
    engine="$CONTAINER_ENGINE"
elif command -v podman >/dev/null 2>&1; then
    engine="podman"
elif command -v docker >/dev/null 2>&1; then
    engine="docker"
else
    echo "Podman or Docker is required for the Linux build." >&2
    exit 1
fi

case "$engine" in
    podman|docker) ;;
    *)
        echo "Unsupported container engine: $engine" >&2
        exit 2
        ;;
esac

version="$(sed -n 's/^#define VERSION "\([^"]*\)"/\1/p' "$repo/uxplay.cpp" | head -n 1)"
if [[ -z "$version" ]]; then
    echo "Cannot read the UxPlay version from uxplay.cpp." >&2
    exit 1
fi

fork_revision="${UXPLAY_FORK_REVISION:-7}"
package_version="${version}.${fork_revision}"
image="${UXPLAY_BUILD_IMAGE:-uxplay-linux-${target_arch}-build}"

echo "Building UxPlay ${package_version} for Linux ${target_arch} with ${engine}"
"$engine" build \
    --tag "$image" \
    --file "$target_dir/Containerfile" \
    "$target_dir"

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
    bash "/src/scripts/linux-${target_arch}/build.sh"

archive="$repo/dist/uxplay-${package_version}-linux-${target_arch}.tar.gz"
echo "${target_arch} package:"
ls -lh "$archive"
