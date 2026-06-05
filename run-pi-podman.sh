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

# Arguments are mounted as container volumes.
#
# Supported forms:
#   ./run-pi-podman.sh
#     Mounts the current directory at /workspace.
#
#   ./run-pi-podman.sh /host/project /host/other
#     Mounts the first path at /workspace and additional paths under /volumes/.
#
#   ./run-pi-podman.sh /host/project:/workspace /host/cache:/cache:ro
#     Passes explicit Podman-style volume specs through, adding nodev/nosuid and
#     defaulting to rw when no options are supplied.
PROJECT_VOLUME_ARGS=()
USED_VOLUME_TARGETS=()
WORKDIR=""

resolve_plain_path() {
  local path="$1"

  if [[ "$path" = /* ]]; then
    printf '%s' "$path"
  else
    printf '%s/%s' "$PWD" "$path"
  fi
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
    printf '%s,nodev,nosuid' "$volume_spec"
  else
    printf '%s:rw,nodev,nosuid' "$volume_spec"
  fi
}

target_in_use() {
  local target="$1"
  local used_target

  for used_target in "${USED_VOLUME_TARGETS[@]}"; do
    if [[ "$used_target" == "$target" ]]; then
      return 0
    fi
  done

  return 1
}

add_project_volume() {
  local volume_spec="$1"
  local target

  target="$(volume_target "$volume_spec")"
  volume_spec="$(with_default_volume_options "$volume_spec")"

  if [[ -z "$WORKDIR" ]]; then
    WORKDIR="$target"
  fi

  USED_VOLUME_TARGETS+=("$target")
  PROJECT_VOLUME_ARGS+=(--volume "$volume_spec")
}

if [[ $# -eq 0 ]]; then
  add_project_volume "$(resolve_plain_path "$PWD"):/workspace"
else
  volume_index=0
  for volume in "$@"; do
    ((volume_index += 1))

    if [[ "$volume" == *:* ]]; then
      add_project_volume "$volume"
    else
      source_path="$(resolve_plain_path "$volume")"

      if [[ $volume_index -eq 1 ]]; then
        target_path="/workspace"
      else
        mount_name="$(basename "$source_path")"
        if [[ -z "$mount_name" || "$mount_name" == / || "$mount_name" == . ]]; then
          mount_name="volume-$volume_index"
        fi
        base_target_path="/volumes/$mount_name"
        target_path="$base_target_path"
        target_suffix=2
        while target_in_use "$target_path"; do
          target_path="${base_target_path}-${target_suffix}"
          ((target_suffix += 1))
        done
      fi

      add_project_volume "$source_path:$target_path"
    fi
  done
fi

if ! podman image exists "$IMAGE"; then
  podman build -t "$IMAGE" "$SCRIPT_DIR"
fi

podman run --rm -it \
  --name pi-sandboxed \
  --cap-drop=ALL \
  --security-opt no-new-privileges \
  --memory=2g \
  --memory-swap=2g \
  --cpus=4 \
  --ulimit nofile=1024:1024 \
  --ulimit nproc=512:512 \
  --volume "$AGENT_VOLUME:/home/node/.pi/agent:rw,nodev,nosuid" \
  "${PROJECT_VOLUME_ARGS[@]}" \
  --workdir "$WORKDIR" \
  "$IMAGE"
