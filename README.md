# Readme


[Link to ics](https://raw.githubusercontent.com/zewelor/ps_events/refs/heads/main/events.ics)

## Usage


Generate an ICS file from the default Google Sheets CSV:

```bash
./bin/spreadsheet_to_ical > events.ics
```

Generate with a custom CSV URL:

```bash
./bin/spreadsheet_to_ical "https://example.com/events.csv" > events.ics
```

Use the CLI for options:

```bash
./bin/cli -u "https://example.com/events.csv" -o events.ics
```

## Browser Tests

The browser test suite uses Capybara with Selenium. Start the Selenium container:

```bash
docker compose up -d selenium
```

Run the tests with the remote driver:

```bash
APP_HOST=host.docker.internal \
SELENIUM_REMOTE_URL=http://localhost:4444/wd/hub rake test
```

`APP_HOST` should point to the hostname that Selenium can use to reach the test
server. On Docker Desktop, `host.docker.internal` works by default. You can also
set `SELENIUM_REMOTE_URL` and `APP_HOST` in your `.env` file for Docker Compose.
