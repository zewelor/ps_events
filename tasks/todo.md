# TODO

- [x] Add shared PWA install UI so the banner is available outside the homepage
- [x] Add a persistent footer install entry point for mobile users
- [x] Rewrite the PWA install controller with prompt-ready and manual fallback states
- [x] Build and verify the generated site plus mobile install flows
- [x] Run `rubocop -a` and the full test suite

## Review

- Shared install UI now renders from the default layout, so install guidance is no longer limited to the homepage.
- Mobile users now keep a footer CTA after closing the banner, which preserves a later path to install.
- The floating install banner now hides automatically when the footer install CTA is already visible on screen, so the same action is not duplicated at the bottom of the viewport.
- Manual fallback instructions were simplified in pt-PT and verified for Android-style, Samsung Internet, and iPhone/Safari mobile user agents in the local preview.
- Added a visible `Privacidade` page plus a footer link that explains the 7-day `localStorage` banner dismissal in pt-PT.
- Added a build-based SEO smoke test for homepage metadata so `title`, `description`, `keywords`, and `lang` are checked automatically.
- Homepage now contains the exact visible phrase `pxopulse`, and the homepage `description` also includes the same exact-match string.
- Verification completed with `source dockerized.sh; jekyll build --source /app/events_listing`, `source dockerized.sh; rubocop -a`, and `source dockerized.sh; rake test`.

## Current Fix

- [x] Add `data-end-date` to rendered event cards for span-aware filtering
- [x] Update date filtering and category counts to use inclusive event span overlap
- [x] Render calendar dots for all days covered by a multi-day event
- [x] Clear stale week/day highlights when a selected date is toggled off
- [x] Re-run build, tests, and manual calendar verification

## Current Review

- Multi-day events now stay visible for any selected day or week that overlaps their start/end span, and category counts use the same overlap rule.
- Calendar dots now render on every covered day of a multi-day event instead of disappearing after the start date.
- Clicking a day inside a selected week now narrows the filter to that single day; clicking that same single day again clears all selected cells, removes the active week chevron, and restores `Todas as Datas` as the active quick filter.
- Verification completed with `source dockerized.sh; bundle exec jekyll build --source /app/events_listing`, `source dockerized.sh; rubocop -a`, `source dockerized.sh; rake test`, and manual browser checks on the local preview for `2026-04-06` plus the `08/03–14/03` to `09/03` interaction path.

## Current Follow-up

- [x] Update the expected interaction so clicking a day inside a selected week narrows the filter to that day
- [x] Re-run validation for the updated week-to-day interaction

- Manual verification confirmed:
- `08/03–14/03` -> `09/03` narrows to only `2026-03-09`
- clicking `09/03` again clears the date filter and restores `Todas as Datas`
