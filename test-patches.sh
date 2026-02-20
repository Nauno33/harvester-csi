#!/bin/bash
set -e

UPSTREAM_REPO="https://github.com/harvester/harvester-csi-driver.git"
TAG="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$TAG" ]; then
  echo "Usage: $0 <upstream-tag>"
  echo "Example: $0 v0.2.4"
  exit 1
fi

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

echo "==> Cloning upstream ${TAG}..."
git clone --depth 1 --branch "${TAG}" "${UPSTREAM_REPO}" "${WORKDIR}/src"

echo "==> Applying patches..."
cd "${WORKDIR}/src"
for patch in "${SCRIPT_DIR}/patches/"*.patch; do
  echo "  Patch: $(basename ${patch})"
  git apply "${patch}" || {
    echo "ERROR: $(basename ${patch}) is incompatible with ${TAG}"
    exit 1
  }
done

echo "==> Copying Dockerfile..."
cp "${SCRIPT_DIR}/Dockerfile" "${WORKDIR}/src/Dockerfile"

echo "==> Updating Go version from go.mod..."
GO_VERSION=$(grep '^go ' go.mod | awk '{print $2}' | cut -d. -f1,2)
echo "  Go version required: ${GO_VERSION}"
sed -i "s|FROM golang:.*AS builder|FROM golang:${GO_VERSION} AS builder|" Dockerfile

echo "==> Building image (dry-run)..."
docker build -f Dockerfile -t "harvester-csi-talos-test:${TAG}" . && \
  echo "" && \
  echo "✅ All patches apply cleanly on ${TAG}" && \
  echo "✅ Build successful: harvester-csi-talos-test:${TAG}" || \
  echo "❌ Build failed"