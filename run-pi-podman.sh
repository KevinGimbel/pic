#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PI_VERSION="$(sed -nE 's/^ENV[[:space:]]+PI_VERSION="?([^"]+)"?$/\1/p' "$SCRIPT_DIR/Containerfile" | head -n1)"

if [[ -z "$PI_VERSION" ]]; then
  echo "Could not determine PI_VERSION from $SCRIPT_DIR/Containerfile" >&2
  exit 1
fi

IMAGE="${PI_SANDBOX_IMAGE:-pi-sandbox:pi-${PI_VERSION}-node24}"
AGENT_VOLUME="${PI_SANDBOX_AGENT_VOLUME:-pi-sandbox-agent}"

# Do not allow mounting $HOME by default
ALLOW_MOUNT_HOME=false

# Additional volumes are configured explicitly with:
#   --volume volumeConfig
#   -v volumeConfig
#
# volumeConfig is a Podman-style volume string, for example:
#   /host/path:/container/path:ro
#
# The current directory is always mounted at /workspace. Every argument except
# --volume/-v and their value is passed to the container entrypoint.
PROJECT_VOLUME_ARGS=()
CONTAINER_ARGS=()

usage() {
  cat >&2 <<'EOF'
Usage: run-pi-podman.sh [--allow-mount-home] [--usage] [--volume volumeConfig|-v volumeConfig]... [container args...]

--allow-mount-home      Allow mounting the $HOME directory into the container
--usage                 Show this usage message
--volume | -v           Mount a volume to a path inside the container

The current directory is always mounted at /workspace inside the container

volumeConfig must be a Podman-style volume string such as:
  /host/path:/container/path[:options]

All arguments except the ones listed above are passed to pi inside the
container. For example, the following restores a session:

pic --session 019ecbc6-4f58-7bac-acb4-5ef04a3edeb9
EOF
}

volume_target() {
  local volume_spec="$1"
  local target="${volume_spec#*:}"
  target="${target%%:*}"

  if [[ -z "$target" || "$target" != /* ]]; then
    echo "Invalid volume '$volume_spec': expected SOURCE:CONTAINER_PATH[:OPTIONS]" >&2
    exit 1
  fi

  printf '%s' "$target"
}

with_default_volume_options() {
  local volume_spec="$1"

  if [[ "$volume_spec" == *:*:* ]]; then
    printf '%s,nodev,nosuid,noexec' "$volume_spec"
  else
    printf '%s:rw,nodev,nosuid,noexec' "$volume_spec"
  fi
}

add_project_volume() {
  local volume_spec="$1"
  local target

  target="$(volume_target "$volume_spec")"
  if [[ "$target" == /workspace ]]; then
    echo "Invalid volume '$volume_spec': /workspace is reserved for the current directory" >&2
    exit 1
  fi

  volume_spec="$(with_default_volume_options "$volume_spec")"

  PROJECT_VOLUME_ARGS+=(--volume "$volume_spec")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --volume|-v)
      if [[ $# -lt 2 ]]; then
        usage
        echo "$1 requires a volumeConfig argument" >&2
        exit 1
      fi
      add_project_volume "$2"
      shift 2
      ;;
    --usage)
        usage
        exit
        ;;
    --allow-mount-home)
      ALLOW_MOUNT_HOME=true
      shift 1
      ;;
    *)
      CONTAINER_ARGS+=("$1")
      shift
      ;;
  esac
done

if ! podman image exists "$IMAGE"; then
  podman build -t "$IMAGE" "$SCRIPT_DIR"
fi

for DIR in "$HOME/.pi/agent/skills" "$HOME/.agents/skills" "$HOME/.opencode/skills" "$HOME/.claude/skills"; do
    if [ -d "$DIR" ]; then
        volume_spec="$DIR:/home/node/.pi/agent/skills:ro,nodev,nosuid,noexec"
        PROJECT_VOLUME_ARGS+=(--volume "$volume_spec")
        break
    fi
done

CONTAINER_UID="$$"

# Prevent accidentally mounting $HOME, and warn about exposure
if [[ "$PWD" == "$HOME" ]]; then
  echo "WARNING: mounting \$HOME as /workspace exposes all configurations."
  if [[ "x$ALLOW_MOUNT_HOME" != "xtrue" ]]; then
    echo "ERROR: Mounting \$HOME is not allowed, run with --allow-mount-home to allow mounting of \$HOME directory"
    exit 1
  fi
fi

podman run --rm -it \
  --name pi-sandboxed-$CONTAINER_UID \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  --memory=2g \
  --memory-swap=2g \
  --cpus=4 \
  --ulimit nofile=1024:1024 \
  --ulimit nproc=512:512 \
  --volume "$AGENT_VOLUME:/home/node/.pi/agent:rw,nodev,nosuid,noexec" \
  --volume "$PWD:/workspace:rw,nodev,nosuid" \
  "${PROJECT_VOLUME_ARGS[@]}" \
  --workdir /workspace \
  "$IMAGE" \
  "${CONTAINER_ARGS[@]}"
