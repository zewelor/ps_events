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
