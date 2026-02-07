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

e2e_install:
  npx -y @playwright/test@latest install

# Run Playwright e2e tests against http://localhost:4000
# Ensure: docker compose up jekyll (in another terminal)
e2e:
  npx -y @playwright/test@latest test e2e/tests --config=e2e/playwright.config.ts

# Generate API key for OCR bearer auth
gen_api_key:
  ruby bin/gen_api_key.rb
