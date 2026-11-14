# Local Docker workspace

Run the sourced aliases, `just`, or `./dockerized.sh compose ...` from the project
root. `docker-compose.yml` mounts the checkout once at its absolute host path.
`app`, `jekyll` and `sinatra` use that same path as their working directory.

CI and production retain their `/app` layout. Rootless Docker and the existing
UID/GID mapping remain required; no host file ownership changes are needed.
