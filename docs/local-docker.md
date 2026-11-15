# Local Docker workspace

Run the activated project commands, `just`, or `./dockerized.sh compose ...` from the project
root. `docker-compose.yml` mounts the checkout once at its absolute host path.

Source `dockerized.sh` from Bash or Zsh to prepend this checkout's `.dev/bin` to `PATH`. The
`ruby-lsp` command routes through `./dockerized.sh lsp`. Neovim selects it only for buffers
rooted in this checkout. The command remains bound to the selected checkout from any working
directory. Sourcing is silent and does not start Docker; sourcing another checkout moves its
`.dev/bin` to the front.
`app`, `jekyll` and `sinatra` use that same path as their working directory.

CI and production retain their `/app` layout. Rootless Docker and the existing
UID/GID mapping remain required; no host file ownership changes are needed.

Prepare development dependencies explicitly with `./dockerized.sh setup`. Gems live in
`.bundle/gems` and tool caches live in `.dev/cache` inside the selected checkout. Setup creates
both directories as the host user before containers write through the checkout bind mount; no
global `HOME` or `XDG_CACHE_HOME` cache is required. The absolute checkout mount makes local gem
definitions visible to host editors at the same path used by the container.

Stop project containers with `./dockerized.sh compose down` before deleting the checkout. Deleting
it removes its gems and tool caches; Docker images and build layers remain Docker-managed and
require separate explicit cleanup. Existing shared cache directories are left untouched and are not
used by the wrapper. Compose services still require the existing `.env` file described in the README
setup steps.

`./dockerized.sh lsp` starts the project's locked Ruby LSP without starting app services.
It requires the prepared image, cache and lockfile; it never builds, pulls, installs gems
or updates the lockfile. Re-run setup after changing dependencies. Ordinary LSP shutdown
removes its one-off container; a killed Docker client or host crash may require targeted
container cleanup. Existing named Bundler volumes are preserved until deliberately removed.
