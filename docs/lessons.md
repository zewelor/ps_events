# Lessons Learned

- Verify runtime gem API against the actual containerized version before finalizing implementation. In this project, `mini_magick` 5.3.1 requires using helpers like `MiniMagick.convert` (or passing a tool name), so `MiniMagick::Tool::Magick.new` without arguments breaks at runtime.
- When a mobile page has both a sticky/floating CTA and a persistent footer CTA for the same action, hide the floating CTA once the footer CTA is visible in the viewport to avoid redundant UI at the bottom of the screen.
- In the calendar UI, clicking a day inside an already selected week should narrow the filter to that specific day; only clicking an already selected single day should clear the date filter entirely.
- For CI/workflow refactors in this repo, use subagents early and do not report back until workflow YAML is linted, logic is locally simulated for the critical paths, and the required repo verification commands have completed.
- For workflow changes in this repo, avoid adding fallback branches for speculative edge cases unless the user explicitly wants that extra resilience; prefer the simplest deterministic flow first.
- For this repo's CI, prefer a single moving `:ci` image tag over per-commit CI image tags unless the user explicitly asks for stronger determinism.
- In this repo, avoid coupling `jekyll_site` to `docker_checks` unless there is a concrete breakage it prevents; independent workflows are easier to maintain here.
- For workflow work in this hobby repo, prefer the simplest reliable orchestration over perfect determinism, and document any accepted race or trade-off in `AGENTS.md` when it is an intentional choice.
- In GitHub Actions YAML for this repo, quote sentinel SHAs like the all-zero hash; otherwise YAML can coerce them to numeric `0`, which breaks first-push branch detection and can silently block Renovate branch automerge.
- When investigating why Renovate PRs here did not auto-merge, always check both the PR body for `Automerge: Enabled/Disabled by config` and the first branch `push` workflow run, because policy mismatches and first-push CI bugs can stack.
