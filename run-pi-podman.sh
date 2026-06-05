#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$PWD}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PI_VERSION="$(sed -nE 's/^ENV[[:space:]]+PI_VERSION="?([^"]+)"?$/\1/p' "$SCRIPT_DIR/Dockerfile" | head -n1)"

if [[ -z "$PI_VERSION" ]]; then
  echo "Could not determine PI_VERSION from $SCRIPT_DIR/Dockerfile" >&2
  exit 1
fi

IMAGE="${PI_SANDBOX_IMAGE:-pi-sandbox:pi-${PI_VERSION}-node24}"
AGENT_VOLUME="${PI_SANDBOX_AGENT_VOLUME:-pi-sandbox-agent}"

if ! podman image exists "$IMAGE"; then
  podman build -t "$IMAGE" "$SCRIPT_DIR"
fi

ENV_ARGS=()
for key in OPENAI_API_KEY ANTHROPIC_API_KEY; do
  if [[ -n "${!key:-}" ]]; then
    ENV_ARGS+=(--env "$key")
  fi
done

podman run --rm -it \
  --name pi-sandboxed \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  "${ENV_ARGS[@]}" \
  --volume "$AGENT_VOLUME:/home/node/.pi/agent:rw" \
  --volume "$PROJECT_DIR:/workspace:rw" \
  --workdir /workspace \
  "$IMAGE"
