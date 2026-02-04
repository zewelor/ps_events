#!/bin/bash

docker_compose_run() {
  local container_name="$1"
  shift

  local -a tty_flags=()
  if [ -t 0 ] && [ -t 1 ]; then
    tty_flags=(-it)
  else
    tty_flags=(-T)
  fi

  docker compose --progress quiet run --rm "${tty_flags[@]}" "$container_name" "$@"
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
names=("ruby" "rails" "bundle" "rake" "gem" "standardrb" "rubocop" "rspec" "lefthook" "jekyll")

# If script is executed with arguments, run the command directly
if [ $# -gt 0 ]; then
  command="$1"
  shift

  # Check if the command is one of our supported dockerized commands
  if [[ " ${names[@]} " =~ " ${command} " ]]; then
    dockerized_run app "$command" "$@"
  else
    echo "Error: '$command' is not a supported dockerized command."
    echo "Supported commands: ${names[*]}"
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

  export LEFTHOOK_BIN="bin/lefthook" # Set the lefthook bin path
  echo "Dockerized aliasses set"
fi
