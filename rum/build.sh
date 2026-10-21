#!/usr/bin/env zsh
# Build the demo frontend (OTel demo 3.1.0) with Coralogix RUM, inside the minikube VM.
# - Applies rum/frontend-coralogix-rum.patch to a fresh checkout of the demo's src/frontend
# - Uploads browser source maps to Coralogix when CORALOGIX_SOURCEMAP_KEY is set in .env
# - Prints the image tag to put in demo-values.yaml (components.frontend.imageOverride.tag)
set -euo pipefail
cd "${0:A:h}/.."

[[ -f .env ]] && set -a && source .env && set +a

DEMO_TAG=3.1.0
PATCH=rum/frontend-coralogix-rum.patch
# Version = demo tag + patch hash, so a code change yields a new version (and new source maps).
RUM_VERSION="${DEMO_TAG}-cx.$(shasum "$PATCH" | cut -c1-7)"
IMAGE="otel-demo-frontend-rum:${RUM_VERSION}"

# `rum/build.sh --print-tag` just prints the tag (used by setup.sh).
if [[ "${1:-}" == "--print-tag" ]]; then echo "$RUM_VERSION"; exit 0; fi

SRC=$(mktemp -d)
VM_KEY=/tmp/cx_sourcemap_key
cleanup() { rm -rf "$SRC"; minikube ssh -- "sudo rm -f $VM_KEY" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git clone -q --depth 1 --branch "$DEMO_TAG" --filter=blob:none --sparse \
  https://github.com/open-telemetry/opentelemetry-demo.git "$SRC"
git -C "$SRC" sparse-checkout set src/frontend
git -C "$SRC" apply "$PWD/$PATCH"

# The source map key reaches BuildKit as a secret file in the VM (never a build arg), so it
# doesn't appear in build output or image history. An empty file means "skip the upload".
KEY_FILE="$SRC/.cx_sourcemap_key"
( umask 077; printf '%s' "${CORALOGIX_SOURCEMAP_KEY:-}" > "$KEY_FILE" )
minikube cp "$KEY_FILE" "$VM_KEY" >/dev/null
rm -f "$KEY_FILE"
if [[ -n "${CORALOGIX_SOURCEMAP_KEY:-}" ]]; then MAPS=upload; else MAPS=skip; fi
echo "Building $IMAGE inside minikube (source maps: $MAPS)"
minikube image build -t "$IMAGE" -f src/frontend/Dockerfile \
  --build-opt="opt=build-arg:RUM_VERSION=${RUM_VERSION}" \
  --build-opt="opt=build-arg:CORALOGIX_RUM_APPLICATION=${CORALOGIX_RUM_APPLICATION:-Frontend}" \
  --build-opt="opt=build-arg:CORALOGIX_RUM_DOMAIN=${CORALOGIX_RUM_DOMAIN:-US2}" \
  --build-opt="secret=id=cx_sourcemap_key,src=$VM_KEY" \
  "$SRC"

# minikube image build can exit 0 even when buildctl fails; check the image really exists.
minikube image ls | grep -q "$IMAGE" || { echo "Build failed: $IMAGE not found in minikube" >&2; exit 1; }
echo "Built $IMAGE"
