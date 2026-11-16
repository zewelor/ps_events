#!/bin/bash

# Interactive activation must not change the caller's shell options or directory.
if [[ -n "${ZSH_VERSION:-}" ]]; then
  _dockerized_source="${(%):-%x}"
else
  _dockerized_source="${BASH_SOURCE[0]}"
fi
if [[ "$_dockerized_source" != "$0" || "${ZSH_EVAL_CONTEXT:-}" == *:file ]]; then
  _dockerized_shell_runner="$(cd -- "$(dirname -- "$_dockerized_source")" && pwd -P)/dockerized.sh"
  _dockerized_activate_project_bin() {
    local project_bin="$1"
    local previous_bin="${_dockerized_active_bin:-}"
    local path_is_set="${PATH+x}"
    local remaining="${PATH-}"
    local entry result= keep=0 finished

    if [[ "$path_is_set" == x ]]; then
      while :; do
        if [[ "$remaining" == *:* ]]; then
          entry="${remaining%%:*}"
          remaining="${remaining#*:}"
          finished=0
        else
          entry="$remaining"
          finished=1
        fi

        if [[ "$entry" != "$project_bin" ]]; then
          if [[ -z "$previous_bin" || "$entry" != "$previous_bin" ]]; then
            if [[ "$keep" == 0 ]]; then
              result="$entry"
              keep=1
            else
              result="$result:$entry"
            fi
          fi
        fi

        if [[ "$finished" == 1 ]]; then
          break
        fi
      done
    fi

    if [[ "$keep" == 1 ]]; then
      PATH="$project_bin:$result"
    else
      PATH="$project_bin"
    fi
    export PATH
    _dockerized_active_bin="$project_bin"
  }
  _dockerized_activate_project_bin "${_dockerized_shell_runner%/*}/.dev/bin"
  for _dockerized_bin in "${_dockerized_path_functions[@]-}" ruby rails bundle rake gem standardrb rubocop rspec jekyll; do
    if typeset -f "$_dockerized_bin" >/dev/null; then
      unset -f "$_dockerized_bin"
    fi
  done
  unset _dockerized_source _dockerized_shell_runner _dockerized_bin
  return 0
fi
unset _dockerized_source

# Capture the source location before a caller changes its directory.
_dockerized_project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Keep CLI, sourced aliases and editor clients in the same worktree context.
dockerized_context() {
  cd -- "$_dockerized_project_root" || return
  export PWD
  local digest slug
  digest="$(printf '%s' "$PWD" | sha256sum)" || return
  slug="${PWD##*/}"
  slug="${slug,,}"
  slug="${slug//[^a-z0-9_-]/-}"
  export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dev-${slug:0:32}-${digest:0:12}}"
  export DOCKER_BUNDLE_DIR="$PWD/.bundle/gems"
  export DOCKER_CACHE_DIR="$PWD/.dev/cache"
}

dockerized_setup() (
  dockerized_context || exit
  dockerized_require_rootless || exit
  mkdir -p "$DOCKER_BUNDLE_DIR" "$DOCKER_CACHE_DIR" || exit
  docker compose --progress quiet build app || exit
  exec docker compose --progress quiet run --rm --no-deps -T app bundle install
)

# A prepared bundle is required: opening an editor must never build or install.
dockerized_lsp() (
  dockerized_context || exit
  dockerized_require_rootless || exit
  if [[ ! -f Gemfile.lock || ! -d "$DOCKER_BUNDLE_DIR" ]]; then
    echo "Ruby LSP [$PWD]: run ./dockerized.sh setup to prepare the bundle." >&2
    exit 1
  fi
  local image
  image="$(docker compose --progress quiet config --no-env-resolution --images editor)" || exit
  if [[ -z "$image" || "$image" == *$'\n'* ]]; then
    echo "Ruby LSP [$PWD]: expected one editor image in Compose configuration." >&2
    exit 1
  fi
  if ! docker image inspect "$image" >/dev/null; then
    echo "Ruby LSP [$PWD]: app image is missing; run ./dockerized.sh setup." >&2
    exit 1
  fi
  exec docker compose --progress quiet run --rm --no-deps -T --pull never editor
)

dockerized_require_rootless() {
  local docker_security_options
  if ! docker_security_options="$(docker info --format '{{json .SecurityOptions}}')"; then
    echo "Could not verify rootless Docker; refusing to start local containers." >&2
    return 1
  fi
  if [[ "$docker_security_options" != *'"name=rootless"'* ]]; then
    echo "Local containers require rootless Docker; refusing to start." >&2
    return 1
  fi
}

dockerized_compose() (
  dockerized_context || exit
  dockerized_require_rootless || exit
  exec docker compose --progress quiet "$@"
)

docker_compose_run() {
  local container_name="$1"
  shift

  local -a tty_flags=()
  if [ -t 0 ] && [ -t 1 ]; then
    tty_flags=(-it)
  else
    tty_flags=(-T)
  fi

  dockerized_compose run --rm "${tty_flags[@]}" "$container_name" "$@"
}

dockerized_run() {
  local container_name="$1"
  local command="$2"
  shift 2

  case "$command" in
  ruby | bundle | gem)
    docker_compose_run "$container_name" "$command" "$@"
    ;;
  *)
    docker_compose_run "$container_name" bundle exec "$command" "$@"
    ;;
  esac
}

# Declare functions for each name
names=("ruby" "rails" "bundle" "rake" "gem" "standardrb" "rubocop" "rspec" "jekyll")

# If script is executed with arguments, run the command directly
if [ $# -gt 0 ]; then
  command="$1"
  shift

  # Check if the command is one of our supported dockerized commands
  if [[ "$command" == setup ]]; then
    dockerized_setup
  elif [[ "$command" == lsp ]]; then
    dockerized_lsp
  elif [[ "$command" == compose ]]; then
    dockerized_compose "$@"
  elif [[ " ${names[@]} " =~ " ${command} " ]]; then
    dockerized_run app "$command" "$@"
  else
    echo "Error: '$command' is not a supported dockerized command."
    echo "Supported commands: setup lsp compose ${names[*]}"
    exit 1
  fi
else
  # Only set up aliases when sourced without arguments
  for name in "${names[@]}"; do
    unset -f $name 2>/dev/null
    eval "
    function $name() {
      dockerized_run app $name \"\$@\"
    }
    "
  done

  echo "Dockerized aliasses set"
fi
