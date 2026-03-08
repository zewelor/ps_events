# TODO

- [x] Add shared PWA install UI so the banner is available outside the homepage
- [x] Add a persistent footer install entry point for mobile users
- [x] Rewrite the PWA install controller with prompt-ready and manual fallback states
- [x] Build and verify the generated site plus mobile install flows
- [x] Run `rubocop -a` and the full test suite

## Review

- Shared install UI now renders from the default layout, so install guidance is no longer limited to the homepage.
- Mobile users now keep a footer CTA after closing the banner, which preserves a later path to install.
- Manual fallback instructions were simplified in pt-PT and verified for Android-style, Samsung Internet, and iPhone/Safari mobile user agents in the local preview.
- Added a visible `Privacidade` page plus a footer link that explains the 7-day `localStorage` banner dismissal in pt-PT.
- Added a build-based SEO smoke test for homepage metadata so `title`, `description`, `keywords`, and `lang` are checked automatically.
- Homepage now contains the exact visible phrase `pxopulse`, and the homepage `description` also includes the same exact-match string.
- Verification completed with `source dockerized.sh; jekyll build --source /app/events_listing`, `source dockerized.sh; rubocop -a`, and `source dockerized.sh; rake test`.
