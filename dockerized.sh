#!/bin/bash

docker_compose_run_on_exec () {
  local container_name="$1"
  shift

  if docker compose ps | grep -q $container_name
  then
    docker compose --progress quiet exec -it $container_name "$@"
  else
    docker compose --progress quiet run --rm -it $container_name "$@"
  fi
}

# Declare functions for each name
names=("ruby" "rails" "bundle" "rake" "gem" "standardrb" "rubocop" "rspec" "lefthook" "spring" "brakeman" "jekyll")

# If script is executed with arguments, run the command directly
if [ $# -gt 0 ]; then
  command="$1"
  shift

  # Check if the command is one of our supported dockerized commands
  if [[ " ${names[@]} " =~ " ${command} " ]]; then
    docker_compose_run_on_exec app "$command" "$@"
  else
    echo "Error: '$command' is not a supported dockerized command."
    echo "Supported commands: ${names[*]}"
    exit 1
  fi
else
  # Only set up aliases when sourced without arguments
  for name in "${names[@]}"
  do
    unset -f $name 2> /dev/null
    eval "
    function $name() {
      docker_compose_run_on_exec app $name \"\$@\"
    }
    "
  done

  export LEFTHOOK_BIN="bin/lefthook" # Set the lefthook bin path
  echo "Dockerized aliasses set"
fi
