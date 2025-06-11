set shell := ["bash", "-uc"]

up: down
  docker compose up --remove-orphans

down:
  docker compose down

docker_build:
  docker compose build --no-cache

test_dockerignore:
  rsync -avn . /dev/shm --exclude-from .dockerignore

jekyll *args='':
  docker compose run --rm --service-ports jekyll jekyll server --force_polling -l -H 0.0.0.0 -s events_listing {{ args }}

# Run all tests
test:
  @source dockerized.sh > /dev/null ; rake test
