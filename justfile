set shell := ["bash", "-uc"]

up: down
  ./dockerized.sh compose up --remove-orphans

down:
  ./dockerized.sh compose down --remove-orphans

docker_build:
  ./dockerized.sh compose build --no-cache

# Show the files sent to Docker using Docker's own context filtering.
show_dockerignore:
  #!/bin/sh
  set -eu
  LC_ALL=C
  export LC_ALL

  test_dir="$(mktemp -d)"
  trap 'rm -rf "$test_dir"' 0 1 2 3 15
  mkdir -p "$test_dir/context"

  docker build --file - --progress=quiet --output "type=local,dest=$test_dir/context" . >/dev/null <<-'EOF'
  # syntax=docker/dockerfile:1
  #check=skip=CopyIgnoredFile
  FROM scratch
  COPY . /context
  EOF

  find "$test_dir/context/context" \( -type f -o -type l \) -print |
    sed "s#^$test_dir/context/context/##" |
    sort > "$test_dir/included"

  cat "$test_dir/included"
  printf '\n%s\n' '---'
  printf 'Total files:\t%s\n' "$(wc -l < "$test_dir/included" | awk '{print $1}')"
  printf 'Total size:\t%s\n' "$(du -sh "$test_dir/context/context" | awk '{print $1}')"


jekyll *args='':
  ./dockerized.sh compose run --rm --service-ports jekyll bundle exec jekyll server --force_polling -l -H 0.0.0.0 -s events_listing {{ args }}

# Run all tests
test:
  @source dockerized.sh > /dev/null ; rake test

e2e_install:
  npm --prefix e2e ci
  npm --prefix e2e exec -- playwright install --only-shell chromium

# Test the production-rendered Jekyll form against a local HTTP server
e2e:
  ./dockerized.sh compose run --rm --no-deps -T --entrypoint '' -e JEKYLL_ENV=production -e BACKEND_HOST=http://localhost:4000 -e COMMIT_SHA=frontend-tests jekyll bundle exec jekyll build --source events_listing --destination tmp/frontend-tests/site
  npm --prefix e2e test

# Generate API key for OCR bearer auth
gen_api_key:
  ruby bin/gen_api_key.rb
