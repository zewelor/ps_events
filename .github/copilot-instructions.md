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

After making changes, run `rubocop -a` to auto-correct any style issues. Run the tests to ensure everything works as expected.

## Text

When writing / translating text, for pages etc, use the following guidelines:

- Use clear, concise language.
- Write text visibile in the html etc in portuguese from portugal

## Testing

run `rake test` to run the tests.

## Tools

Used in this project

- Jekyll for static site generation.
  - Do not start jekyll build / server. I've already done that in other shell. Its launched with docker-compose
- Tailwind CSS for styling. We are using version 4
- Sinatra for the backend.
  - Dont start the Sinatra server. I've already done that in other shell. Its launched via bin/server
  - Its running on port 4567 via docker-compose. Its accessible at http://sinatra:4567

## UI and Styling

- Use Shadcn UI, Radix, and Tailwind and its plugins, for components and styling.
- Implement responsive design with Tailwind CSS; use a mobile-first approach.
- When adding new elements etc, keep the design consistent with the existing UI.

### Project Structure

- Envs are loaded from the .env file, in docker-compose.yml
- Jekyll site resides in the events_listing directory.
- .github directory contains GitHub Actions workflows. They are used for CI/CD.
- Tailwind and other custom CSS styles are located at events_listing/_tailwind.css
- Gems are managed in the Gemfile located in the root directory.
- Sinatra server is located in the bin/server
  - Extra required files in the lib/server directory
