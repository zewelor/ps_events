# Lessons Learned

- Verify runtime gem API against the actual containerized version before finalizing implementation. In this project, `mini_magick` 5.3.1 requires using helpers like `MiniMagick.convert` (or passing a tool name), so `MiniMagick::Tool::Magick.new` without arguments breaks at runtime.
- When a mobile page has both a sticky/floating CTA and a persistent footer CTA for the same action, hide the floating CTA once the footer CTA is visible in the viewport to avoid redundant UI at the bottom of the screen.
- In the calendar UI, clicking a day inside an already selected week should narrow the filter to that specific day; only clicking an already selected single day should clear the date filter entirely.
