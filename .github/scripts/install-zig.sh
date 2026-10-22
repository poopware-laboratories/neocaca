#!/bin/sh
# Installs the Zig release named by `minimum_zig_version` in build.zig.zon
# (or $1) for this machine, checking the tarball against the SHA-256 that
# ziglang.org publishes, and puts it on the PATH of later GitHub steps.
# For runners where the setup-zig action cannot run, such as Alpine.
set -eu

version=${1:-$(sed -n 's/.*minimum_zig_version = "\(.*\)".*/\1/p' build.zig.zon)}
arch=$(uname -m)
case $(uname -s) in
Linux) os=linux ;;
Darwin) os=macos ;;
FreeBSD) os=freebsd ;;
*) echo "unsupported OS: $(uname -s)" >&2 && exit 1 ;;
esac
platform="$arch-$os"

index=$(curl -fsSL --retry 3 https://ziglang.org/download/index.json)
url=$(printf '%s' "$index" | jq -er --arg v "$version" --arg p "$platform" '.[$v][$p].tarball')
sum=$(printf '%s' "$index" | jq -er --arg v "$version" --arg p "$platform" '.[$v][$p].shasum')

dir=${RUNNER_TEMP:-/tmp}/zig-$version
mkdir -p "$dir"
curl -fsSL --retry 3 -o "$dir/zig.tar.xz" "$url"
echo "$sum  $dir/zig.tar.xz" | sha256sum -c -
tar -xJf "$dir/zig.tar.xz" -C "$dir" --strip-components=1
rm "$dir/zig.tar.xz"

if [ -n "${GITHUB_PATH:-}" ]; then echo "$dir" >>"$GITHUB_PATH"; fi
"$dir/zig" version
