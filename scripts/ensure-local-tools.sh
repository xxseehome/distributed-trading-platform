#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="${TOOLS_DIR:-$repo_root/.tools/bin}"
mkdir -p "$tools_dir"

K3D_VERSION="${K3D_VERSION:-5.8.3}"
HELM_VERSION="${HELM_VERSION:-3.17.3}"
VCLUSTER_VERSION="${VCLUSTER_VERSION:-0.24.0}"
FLUX_VERSION="${FLUX_VERSION:-2.9.4}"

case "$(uname -s)" in
  Darwin) os=darwin ;;
  *) echo "Only macOS is supported by the local runner." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64; helm_arch=arm64 ;;
  x86_64) arch=amd64; helm_arch=amd64 ;;
  *) echo "Unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
esac

need_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

verify_checksum() {
  local file="$1" checksum_file="$2" asset="$3"
  local expected
  expected="$(awk -v asset="$asset" '$NF == asset || $NF == "_dist/" asset {print $1; exit}' "$checksum_file")"
  if [[ -z "$expected" ]]; then
    echo "No checksum entry found for $asset" >&2
    return 1
  fi
  printf "%s  %s\n" "$expected" "$file" | shasum -a 256 -c -
}

download_binary() {
  local name="$1" url="$2" checksum_url="$3" destination="$tools_dir/$1"
  if [[ -x "$destination" ]]; then
    return 0
  fi
  local tmp="${destination}.tmp" checksum_tmp="${destination}.checksums"
  echo "Downloading $name from $url"
  curl --fail --location --retry 3 --proto "=https" --tlsv1.2 "$url" -o "$tmp"
  curl --fail --location --retry 3 --proto "=https" --tlsv1.2 "$checksum_url" -o "$checksum_tmp"
  verify_checksum "$tmp" "$checksum_tmp" "$(basename "$url")"
  rm -f "$checksum_tmp"
  chmod 0755 "$tmp"
  mv "$tmp" "$destination"
}

need_command curl
need_command shasum
need_command kubectl
need_command docker

# Official release URLs are the default. LOCAL_TOOL_MIRROR_BASE may point to a
# byte-for-byte mirror, but the downloaded release must still pass its checksum.
mirror="${LOCAL_TOOL_MIRROR_BASE:-}"
github_base="${mirror:-https://github.com}"

if ! command -v k3d >/dev/null 2>&1 && [[ ! -x "$tools_dir/k3d" ]]; then
  asset="k3d-${os}-${arch}"
  download_binary k3d \
    "$github_base/k3d-io/k3d/releases/download/v${K3D_VERSION}/${asset}" \
    "$github_base/k3d-io/k3d/releases/download/v${K3D_VERSION}/checksums.txt"
fi

if ! command -v helm >/dev/null 2>&1 && [[ ! -x "$tools_dir/helm" ]]; then
  tmp_dir="$(mktemp -d)"
  helm_archive="helm-v${HELM_VERSION}-${os}-${helm_arch}.tar.gz"
  curl --fail --location --retry 3 --proto "=https" --tlsv1.2 \
    "https://get.helm.sh/${helm_archive}" -o "$tmp_dir/$helm_archive"
  curl --fail --location --retry 3 --proto "=https" --tlsv1.2 \
    "https://get.helm.sh/helm-v${HELM_VERSION}-${os}-${helm_arch}.tar.gz.sha256sum" \
    -o "$tmp_dir/helm.sha256"
  (cd "$tmp_dir" && shasum -a 256 -c helm.sha256)
  tar -xzf "$tmp_dir/$helm_archive" -C "$tmp_dir"
  install -m 0755 "$tmp_dir/${os}-${helm_arch}/helm" "$tools_dir/helm"
  rm -rf "$tmp_dir"
fi

if ! command -v vcluster >/dev/null 2>&1 && [[ ! -x "$tools_dir/vcluster" ]]; then
  asset="vcluster-${os}-${arch}"
  download_binary vcluster \
    "$github_base/loft-sh/vcluster/releases/download/v${VCLUSTER_VERSION}/${asset}" \
    "$github_base/loft-sh/vcluster/releases/download/v${VCLUSTER_VERSION}/checksums.txt"
fi

if ! command -v flux >/dev/null 2>&1 && [[ ! -x "$tools_dir/flux" ]]; then
  tmp_dir="$(mktemp -d)"
  flux_archive="flux_${FLUX_VERSION}_${os}_${arch}.tar.gz"
  curl --fail --location --retry 3 --proto "=https" --tlsv1.2 \
    "$github_base/fluxcd/flux2/releases/download/v${FLUX_VERSION}/${flux_archive}" \
    -o "$tmp_dir/$flux_archive"
  curl --fail --location --retry 3 --proto "=https" --tlsv1.2 \
    "$github_base/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_checksums.txt" \
    -o "$tmp_dir/flux.checksums"
  verify_checksum "$tmp_dir/$flux_archive" "$tmp_dir/flux.checksums" "$flux_archive"
  tar -xzf "$tmp_dir/$flux_archive" -C "$tmp_dir"
  install -m 0755 "$tmp_dir/flux" "$tools_dir/flux"
  rm -rf "$tmp_dir"
fi

export PATH="$tools_dir:$PATH"
for tool in k3d helm vcluster flux kubectl; do
  printf "%-10s " "$tool"
  "$tool" version --short 2>/dev/null || "$tool" version --client --short 2>/dev/null || true
done
