# Readme


[Link to ics](https://raw.githubusercontent.com/zewelor/ps_events/refs/heads/main/events.ics)

## Setup

- cp .env.example .env
- source dockerized.sh
- lefthook install -f

Local development requires rootless Docker. Compose uses container UID/GID
`0:0`, which maps to the unprivileged host user running the daemon and allows
writes to the checkout without changing host permissions. See Docker's
[UID/GID mapping documentation](https://docs.docker.com/engine/security/rootless/uid-gid-mapping/).

`dockerized.sh` checks the connected daemon before each Compose command and
refuses rootful Docker or a failed inspection. Use `just up`, `just jekyll`,
the sourced aliases, or `./dockerized.sh compose ...` for local work. VS Code
Dev Containers checks the daemon during host initialization. Direct
`docker compose` commands bypass the check and must connect to the rootless
daemon. CI invokes Compose directly with `docker-compose.ci.yml`, keeping its
separate image and user configuration.

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


### OCR failure responses

`POST /events_ocr` returns HTTP 503 with `error_code: "ocr_temporarily_unavailable"`
when the model is temporarily unavailable during analysis, before any events are
saved. Clients may retry that explicit response with bounded backoff.

Quota failures keep HTTP 429 with `rate_limit_exceeded`. Saving failures return
HTTP 503 with `ingestion_failed`, including confirmed results before the failure.
A generic 503, timeout, or lost
response does not guarantee that nothing was saved. Do not automatically repeat
those uploads without checking the persisted events.

### Duplicate feedback

All ingestion paths check the live configured target and `Approved` before an
append, with columns resolved by their headers, including links. An unavailable
read, missing headers or malformed stored dates prevents unchecked writes.

Already covered event content returns HTTP 200, `outcome: "skipped"`, and the
existing row reference. Comparison normalizes valid dates, case outside URLs,
whitespace and ordinal spelling in names (`22º` / `22.º`); submission timestamps,
submitter and image UUIDs are ignored. URL path case is preserved, including URLs
embedded in descriptions. Optional blank end dates mean the start date.
Incoming contacts and links may be omitted when all other event content matches;
any supplied contact or link must match the stored value. Missing times do not
match known times. New or changed information remains a conflict, including
description changes, even when the occurrence appears to be the same. There is
no automatic correction or merge of an existing row.

Potential matches return HTTP 409 and `status: "needs_review"`. Both endpoints
return `counts: {added, skipped, conflicted}` and per-event `results`. Conflicts
include the submitted `event`, candidate `event` data, `reference`, `differences`
and a `fingerprint`. Same-start-date matches are deliberately conservative, as
OCR can change both the title and venue wording. Overlapping events at the same
venue also reach review, including tournaments inside an older aggregate entry.
These are candidates, not proof of duplication.

The form preserves its data, shows the submitted and stored values for every
differing field, and offers **Não guardar esta submissão** (no changes saved) or
**É outro evento**. New or corrected facts about the same occurrence remain for
review; treating them as a distinct occurrence would append another row.
The latter action resubmits that event to `/add_event` with
`distinct_from`, a JSON array of the candidate fingerprints being explicitly
acknowledged. Fingerprints bind the input, existing event content and row reference;
changed data is checked again. Already covered content is always skipped, even with
an acknowledgement. OCR review submits only the selected occurrence, without
rerunning extraction or resubmitting successful earlier occurrences.
On a partial failure, earlier conflicts remain reviewable; failed or unattempted
occurrences are not automatically retried. The failure summary and source inputs
remain available for checking the uncertain outcome.

OCR processes events in order, updating one request-local index after every
confirmed append. A save failure stops the remaining appends; results identify
confirmed additions, the failed occurrence (its write outcome may be unknown),
and unattempted occurrences. The next request rebuilds the live index, so an
equivalent retry skips earlier successes, including lost append responses.

`AddEventService#add_event` now returns a hash with `status: "added"` and `range`,
`status: "skipped"` and `existing_row`, or `status: "conflict"` and candidates.
CLI `bin/add_event` prints this feedback; conflicts exit with status 2. A skipped
or conflicting event does not publish another image through these ingestion paths.

Limits: this is a read-before-append check, not a transactional concurrency lock.
Simultaneous requests can still race. There is no durable source/occurrence identity
or automatic semantic adjudication in this change. A resized/recompressed source
has different bytes; the same image alone cannot identify each occurrence.
Integrating the feedback into r3x and persisting stable identities remain separate
work. Do not automatically replay a flyer and assume wording/date changes are
fully deduplicated. This change does not edit or hide existing sheet rows.

Run Ruby coverage with `./dockerized.sh rake test`. The two browser-independent
JavaScript recovery regressions use Node's built-in runner:
`node test/upload_form_test.js` (no npm dependencies).

Generate an ICS file from the default Google Sheets CSV:

```bash
./bin/spreadsheet_to_ical > events.ics
```

Generate with a custom CSV URL:

```bash
./bin/spreadsheet_to_ical "https://example.com/events.csv" > events.ics
```
