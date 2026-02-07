# Readme


[Link to ics](https://raw.githubusercontent.com/zewelor/ps_events/refs/heads/main/events.ics)

## Setup

- cp .env.example .env
- source dockerized.sh
- lefthook install -f

Run hooks via the dockerized aliases:

```bash
source dockerized.sh; lefthook run pre-commit
```

## Usage


### API Authentication (OCR)

Endpoint `/events_ocr` pode ser chamado com Bearer token em vez de Google OAuth.

**Configurar no .env:**

```bash
API_KEYS=token1:email1@example.com,token2:email2@partner.pl
```

**Gerar um token (CLI):**

```bash
just gen_api_key
```

**Exemplo de chamada:**

```bash
curl -X POST http://localhost:4567/events_ocr \
  -H "Authorization: Bearer SEU_TOKEN" \
  -F "event_image=@plakat.jpg"
```


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
