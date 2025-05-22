set shell := ["bash", "-uc"]

docker_build:
  docker compose build --no-cache

test_dockerignore:
  rsync -avn . /dev/shm --exclude-from .dockerignore

jekyll *args='':
  source dockerized.sh > /dev/null && jekyll server --force_polling -l -H 0.0.0.0 -s events_listing {{ args}}
