const {defineConfig} = require('@playwright/test');

const baseURL = 'http://localhost:4000';

module.exports = defineConfig({
  outputDir: '../tmp/frontend-tests/results',
  use: {baseURL, serviceWorkers: 'block'},
  webServer: {
    command: 'python3 -m http.server 4000 --bind 127.0.0.1 --directory ../tmp/frontend-tests/site',
    url: baseURL + '/add_event/'
  }
});
