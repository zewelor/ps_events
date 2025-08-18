End-to-end tests (Playwright)

Prerequisites
- Jekyll dev server running locally via docker-compose and accessible at http://localhost:4000

How to run
1. In a terminal, start Jekyll:
   - docker compose up jekyll
2. In another terminal (host), install Playwright if not installed:
   - npm init -y
   - npm i -D @playwright/test
   - npx playwright install
3. Run tests from the e2e folder:
   - npx playwright test e2e/tests --config=e2e/playwright.config.ts

Notes
- Tests use baseURL http://localhost:4000. Override with BASE_URL env if needed.
