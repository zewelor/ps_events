# Instructions

You are an expert in Ruby / Jekyll and Tailwind.
You are following all of the best modern practices and conventions.
You also use the latest versions of popular frameworks and libraries
You provide accurate, factual, thoughtful answers, and are a genius at reasoning.

Its MVP so lets keep it simple and focus on the core functionality.

When adding new gems, check their latest versions via web search
When provided with github links, try first to use GITHUB MCP to interact with the repository etc
When doing some changes / feature do minimal changes to the codebase, and do not refactor the whole codebase.
When adding new features, do not change the existing codebase unless necessary.
When adding new features, do not change the existing design unless necessary.
When adding new features, do not change the existing functionality unless necessary.

After making changes, run `rubocop -a` to auto-correct any style issues. Run the tests to ensure everything works as expected. Run it on the whole codebase, not just the changed files. Its only for .rb files.

## Text

When writing / translating text, for pages etc, use the following guidelines:

- Use clear, concise language.
- Write text visibile in the html etc in portuguese from portugal
- Write the brand name as `PXO Pulse`; keep lowercase `pxopulse` only in technical identifiers such as URLs, email addresses, and social handles.
- In public-facing pt-PT copy, follow local Porto Santo usage: write `no Porto Santo`, `do Porto Santo`, and `ao Porto Santo`. Also use sentence case for UI labels and prefer `respetiva` over ambiguous possessives such as `sua` when referring back to an item.
- After changing user-visible pt-PT copy, run `source dockerized.sh; ruby bin/linguistic_audit [changed_file ...]`. With no arguments it audits `events_listing/index.html` and `events_listing/about_us.html`. Review its suggestions before applying them and treat a non-zero status as a failed audit.

## Testing

This project is dockerized. To run commands in the containerized environment, you should use the helper script.
The preferred way to run tests is:

```bash
source dockerized.sh; rake test
```

This will ensure the aliases are set up correctly before running the tests.

When updating GitHub Actions workflows, always run Ruby/Jekyll-related commands via `bundle exec` (for example inside `docker compose run ... app`), to avoid PATH/binstub differences across Bundler versions.

If code during tests output anything on the console, capture it using capture_io

## Tools

Used in this project

- Jekyll for static site generation.
  - Inside container its available at http://jekyll:4000
- Tailwind CSS for styling. We are using version 4
- Sinatra for the backend.
  - Its running on port 4567 via docker-compose. Its accessible at http://sinatra:4567

### MCP tools

- When using playwright, use localhost:4000 as host

### Helper scripts

- `bin/add_event <image_path> <event_json_or_file_path> [submitter_email]`
  - Helper script to process a local flyer image (webp conversion, resizing, stripping metadata) and save it to `events_listing/assets/images/UUID.webp`.
  - Attempts to upload the image to GitHub using `GitHubService` (if credentials are set).
  - Appends the event metadata row to the Google Sheet configured in `.env`.
  - **JSON Format**: The event JSON can be passed as a string or path to a JSON file. It should contain the following fields:
    ```json
    {
      "name": "Nome do Evento",
      "start_date": "15/06/2026",
      "start_time": "21:00",
      "end_date": "15/06/2026",
      "end_time": "23:59",
      "location": "Localização",
      "description": "Descrição do evento",
      "category": "Música",
      "organizer": "Organizador",
      "contact_email": "contacto@email.com",
      "contact_tel": "912345678",
      "price_type": "Gratuito",
      "event_link1": "https://...",
      "event_link2": "",
      "event_link3": "",
      "event_link4": ""
    }
    ```
  - **Manual Reading Requirement**: When requested to add an event from a flyer image/PDF, do not run the OCR tools or scripts (`bin/ocr`, etc.) to analyze it. Instead, read the file directly yourself using the appropriate file viewing tool, extract the event details manually, create the JSON payload, and then run `bin/add_event`.
  - **Approval Reminder Requirement**: After successfully running the `bin/add_event` script, always remind the user in English (not in Portuguese) that they need to approve/accept the added event in the Google Spreadsheet.

- `bin/convert_image <image_path>`
  - Standalone helper script to process, optimize, and upload a local flyer image (converting to WebP, resizing, stripping metadata). Saves the optimized file to `events_listing/assets/images/UUID.webp` and returns the generated UUID.

- `bin/investigate_sheet [options]`
  - Read-only inspection of the events spreadsheet. Use it as the source of truth about what is currently published, instead of grepping `events.csv`, which is a downloaded snapshot and lags behind the sheet.
  - Options: `--image UUID`, `--search TEXT`, `--date DD/MM/YYYY`, `--range RANGE`, `--limit N`, `--duplicates`, `--invalid`, `--help`.
  - Run it with `./dockerized.sh ruby bin/investigate_sheet ...` so the gems and `.env` are loaded for you. The other `bin/*` scripts carry a `#!/dockerized.sh ruby` shebang that does not resolve, so they only run through this wrapper too.
  - Filters apply to the whole output, including the `--duplicates` and `--invalid` sections.
  - See the dedicated section below for the workflow it supports.

### Investigating the spreadsheet

`events_listing/_data/events.csv` is a symlink to the root `events.csv`, and both are refreshed
from the Google Sheet by CI. That makes them a stale mirror: rows you just appended, or edits the
user made in the spreadsheet, will not be visible there. Always inspect the sheet directly.

| Command | Use it to |
|---|---|
| `./dockerized.sh ruby bin/investigate_sheet --image UUID` | List every event sharing one flyer, which is how you confirm a batch landed and spot duplicates |
| `./dockerized.sh ruby bin/investigate_sheet --date 03/10/2026` | See everything running on a day, multi-day spans included, to sanity-check date concentration |
| `./dockerized.sh ruby bin/investigate_sheet --search "golf"` | Find events by name, location, description, organizer or category |
| `./dockerized.sh ruby bin/investigate_sheet --duplicates` | Report exact duplicates and same-day/same-place/same-category lookalikes |
| `./dockerized.sh ruby bin/investigate_sheet --invalid` | Report rows that fail `lib/server/event_validation.rb` |

Notes on interpreting the output:

- **Row numbers are spreadsheet row numbers**, so they can be used to locate and delete a row in the
  spreadsheet, including custom ranges whose header starts below row 1. They are not CSV line numbers.
- `--date` accepts one or two digits for day/month and exactly four digits for the year. Malformed
  or impossible filter dates fail before the spreadsheet is read.
- `--invalid` validates dates exactly as read from the sheet. Both dates accept one or two digits
  for day/month and exactly four digits for the year, so `3/10/2026` and `03/10/2026` are valid.
  Malformed and impossible dates are reported without correcting them. `AddEventService` validates
  every event before appending it; `bin/add_event` also validates before processing or uploading the
  flyer. Valid date text is preserved. `Event#canonical_start_date` only pads valid dates for
  duplicate grouping, because `5/6/2026` and `05/06/2026` represent the same day.
- `--invalid` runs the full `EventValidation` check, which is the JSON schema in
  `lib/event_schema.json` plus relational rules (end date not before start date, end time after
  start time on same-day events), so a row can be reported for a reason that is not in the schema
  itself.
- `--duplicates` mixes two checks. *Exact duplicates* share a name and start date. *Suspicious
  duplicates* share a day, place and category but differ in name, which is the heuristic that
  catches the same tourney added twice under different wording. It is a prompt to look, not a
  verdict: two genuinely different events can share a venue and date (e.g. two golf tournaments on
  the same day at the same course). Expect false positives here and judge each hit by eye.
- `price_type` must be exactly `Gratuito`, `Pago` or `Desconhecido`. The value `Grátis` is common
  in the sheet and is reported as a violation. Likewise `contact_tel` accepts only digits, spaces,
  dashes, brackets and `+`, so a combined number like `291 985 289 / 924 366 168` is flagged.

**Adding several events from one flyer**: `bin/add_event` handles a single event per call and
re-processes the image every time. For recurring or multi-event flyers, run `bin/convert_image`
once, then write a scratch script that loops over the events and calls
`SheetsConfig.add_event_service.add_event(event, submitter_email:, image_path:)` with the shared
UUID. `SheetsConfig` (in `lib/server/sheets_config.rb`) is where new bin scripts should get the
spreadsheet ID, the range and the services from, so use it instead of re-reading `ENV` yourself.
`bin/server.rb` still wires its own, because it swaps in a nil service under `APP_ENV=test`.

### Recurring & Shared Flyer Events Guidelines

- **Efficient Recurring/Shared Event Workflow**: When adding multiple occurrences of a recurring event (e.g. weekly events) or multiple distinct events listed on the same flyer/poster, do not run `bin/add_event` multiple times with the raw image. Instead:
  1. Process the image once using `bin/convert_image <image_path>` to obtain a single image UUID.
  2. Write a scratch script to append the multiple event rows to Google Sheets (using `AddEventService#add_event`) and pass the generated UUID as the shared `image_path` value for each row.
  3. This ensures only a single WebP file is stored in git and prevents redundant API requests.

- **Check for Duplicates**: Always check the existing events in `events_listing/_data/events.csv` before converting/uploading the image or adding new rows. Cross-reference by name, date, and location. Do not add events that are already registered.

- **Event Granularity**: When a flyer contains separately named/date-specific sub-events under a generic heading (e.g. multiple individual golf tournaments on different days, or different daily concerts in an animation cycle), add **one row per sub-event** rather than one long-running/aggregated event. Give each sub-event its correct individual date, time, and specific name, and link them all to the shared flyer image UUID. If the flyer advertises one named event with a date range (e.g. an expo or festival running from one date to another), add one row with the correct `start_date` and `end_date` instead.


## UI and Styling

- Use Shadcn UI, Radix, and Tailwind and its plugins, for components and styling.
- Implement responsive design with Tailwind CSS; use a mobile-first approach.
- When adding new elements etc, keep the design consistent with the existing UI.

### UI Validation Checklist

- Start (or ensure running) the Jekyll container and preview via `http://jekyll:4000` using the Simple Browser when verifying UI changes.
- Confirm styles are compiled by checking that `events_listing/_site/assets/css/styles.css` includes the new utilities (re-run `bundle exec jekyll build` if unsure).
- Exercise critical flows manually: calendar navigation, filter buttons, and event cards should render correctly in both desktop and mobile breakpoints (use the Simple Browser's responsive toolbar or narrow the viewport).
- Verify interactive affordances: hover states on buttons, visible calendar event dots, and consistent spacing around toolbar groups.
- After visual review, run `bundle exec rubocop -a` and `rake test` to keep lint/tests green before handing work back.

### Calendar Component Requirements

- Month navigation, quick filters (“Todas as Datas”, “Hoje”, “Esta semana”), and inline day selection must coexist without console errors or broken styles.
- Event dots must remain visible against the day background at all breakpoints; ensure each category still maps to a distinct colour.
- Week selector column should align flush with the calendar grid and reuse existing button styles/colours from the design system.
- Maintain a single-frame look around the grid (no double borders) and keep row heights comfortable on desktop and mobile.
- Keep accessibility simple: semantic buttons, polite month title updates, and focus outlines on actionable elements are required—avoid reintroducing heavy ARIA state tracking unless necessary.

### Project Structure

- Envs are loaded from the .env file, in docker-compose.yml
- Jekyll site resides in the events_listing directory.
- .github directory contains GitHub Actions workflows. They are used for CI/CD.
- Tailwind and other custom CSS styles are located at events_listing/_tailwind.css
- Gems are managed in the Gemfile located in the root directory.
- Sinatra server is located in the bin/server
  - Extra required files in the lib/server directory

## Workflow Orchestration

### Workflow Diagram Maintenance
- Keep the GitHub Actions dependency diagram in `.github/workflows/README.md` up to date whenever any workflow trigger, `workflow_run` link, concurrency rule, auto-commit behavior, or cross-workflow dependency changes.
- The Mermaid chart must stay embedded in a fenced code block using ```` ```mermaid ````.
- After editing that chart, validate the Mermaid syntax before finishing the task.
- When GitHub workflow logic changes, update both the workflow files and the diagram in the same task so the documentation does not drift.

### Conscious Workflow Trade-offs
- Keep GitHub Actions orchestration simple for this hobby project, even if that leaves small, understood races in place.
- `regenerate_events.yml` intentionally reuses the moving `:ci` image for faster daily runs instead of waiting for a per-commit rebuild; if a same-push race happens, the next daily run is expected to pick up the newer image.
- When a push also triggers `regenerate_events.yml`, prefer skipping the push-triggered `jekyll_site.yml` deploy and let the `workflow_run` path be the canonical site deployment for that change.

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

## Code Style

### Naming Conventions
- Use `snake_case` for file names, method names, and variables
- Use `CamelCase` for class and module names
- Follow Ruby naming conventions: methods ending with `?` for predicates, `!` for dangerous operations

### Clean Code Guidelines

#### Constants Over Magic Numbers
- Replace hard-coded values with named constants
- Use descriptive constant names that explain the value's purpose
- Keep constants at the top of the file or in a dedicated constants file

#### Meaningful Names
- Variables, functions, and classes should reveal their purpose
- Names should explain why something exists and how it's used
- Avoid abbreviations unless they're universally understood

#### Smart Comments
- Don't comment on what the code does - make the code self-documenting
- Use comments to explain why something is done a certain way
- Document APIs, complex algorithms, and non-obvious side effects

#### Single Responsibility
- Each function should do exactly one thing
- Functions should be small and focused
- If a function needs a comment to explain what it does, it should be split

## Testing Guidelines

### Test Structure
- Write tests before fixing bugs
- Keep tests readable and maintainable
- Test edge cases and error conditions
- One assertion concept per example; refactor relentlessly

### Best Practices
- Follow TDD/BDD practices where applicable
- Don't test private methods - test behavior through public APIs
- Test only your business logic, not framework functionality
- Keep tests short and concise
- Group related tests in `context` blocks with clear descriptions

### What to Assert
- Status codes and response structure
- Database changes (record creation, updates, state transitions)
- Side effects (emails sent, jobs enqueued)
- User-facing output and content
