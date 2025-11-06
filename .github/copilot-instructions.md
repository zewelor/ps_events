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

run `rake test` to run the tests.

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
