# GitHub Actions Workflow Map

This document tracks the trigger and dependency flow between the repository's GitHub Actions workflows.

Update this chart whenever a workflow trigger, cross-workflow dependency, concurrency rule, or auto-commit path changes.

Solid arrows mean "can trigger / leads to a new workflow or job path". Dotted arrows mean "waits for / depends on" and do not trigger a new workflow.

```mermaid
flowchart TD
    push_regen["push(main)<br/>bin/spreadsheet_to_ical<br/>or regenerate_events.yml"] --> regenerate["regenerate_events.yml<br/>download CSV"]
    schedule_regen["schedule / workflow_dispatch / repository_dispatch"] --> regenerate

    regenerate --> regen_validate["validate regenerated Jekyll build<br/>with :ci image"]
    regen_validate --> regen_commit["auto-commit events.csv<br/>via GITHUB_TOKEN"]
    regen_validate --> regen_complete["workflow_run completed<br/>(success only)"]
    regen_complete --> jekyll["jekyll_site.yml<br/>Build and deploy site"]

    regen_commit -. no push-triggered workflows .-> token_note["GITHUB_TOKEN commits<br/>do not trigger push workflows"]

    push_events["push(main)<br/>events.csv"] --> jekyll
    push_events --> docker_checks["docker_checks.yml<br/>Docker Checks"]

    push_site["push(main)<br/>events_listing/**<br/>or jekyll_site.yml"] --> jekyll
    schedule_site["schedule / workflow_dispatch"] --> jekyll

    push_backend["push(main)<br/>other non-events_listing changes"] --> docker_checks
    pr_backend["pull_request<br/>non-events_listing changes"] --> docker_checks
    dispatch_backend["workflow_dispatch"] --> docker_checks

    docker_checks --> docker_tests["tests job<br/>publishes :ci"]
    docker_checks --> docker_changes["changes job"]
    docker_tests --> docker_production["push_production job"]
    docker_changes --> docker_production

    jekyll -. push only: waits for tests job<br/>on the same commit .-> docker_tests
```
