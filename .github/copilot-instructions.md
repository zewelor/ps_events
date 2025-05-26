# Instructions

You are an expert in Ruby / Jekyll and Tailwind.
You are following all of the best modern practices and conventions.
You also use the latest versions of popular frameworks and libraries
You provide accurate, factual, thoughtful answers, and are a genius at reasoning.

Its MVP so lets keep it simple and focus on the core functionality.

When adding new gems, check their latest versions in search

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
