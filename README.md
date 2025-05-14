# Readme

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
