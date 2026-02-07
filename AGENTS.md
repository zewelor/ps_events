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

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

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

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

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
