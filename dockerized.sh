#!/bin/bash

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

dockerized_compose() {
  dockerized_require_rootless || return 1
  docker compose --progress quiet "$@"
}

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
  if [[ "$command" == compose ]]; then
    dockerized_compose "$@"
  elif [[ " ${names[@]} " =~ " ${command} " ]]; then
    dockerized_run app "$command" "$@"
  else
    echo "Error: '$command' is not a supported dockerized command."
    echo "Supported commands: compose ${names[*]}"
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
