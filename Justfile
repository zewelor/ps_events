set shell := ["bash", "-uc"]

up: down
  podman-compose up --remove-orphans

down:
  podman-compose down

docker_build:
  podman-compose build --no-cache

test_dockerignore:
  rsync -avn . /dev/shm --exclude-from .dockerignore

jekyll *args='':
  podman-compose run --rm --service-ports jekyll jekyll server --force_polling -l -H 0.0.0.0 -s events_listing {{ args }}

# Run all tests
test:
  @source dockerized.sh > /dev/null ; rake test
