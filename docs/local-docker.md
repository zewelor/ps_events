# Local Docker workspace

Run the sourced aliases, `just`, or `./dockerized.sh compose ...` from the project
root. Compose loads `docker-compose.override.yml` automatically and mounts the
checkout once at its absolute host path. `app`, `jekyll` and `sinatra` use that
same path as their working directory.

Dev Containers uses `${localWorkspaceFolder}` for its mount and workspace,
independent of the directory VS Code started in. It starts only `app`; start
`jekyll` and `sinatra` through the host Compose runner when needed. The explicit
Dev Container Compose file list excludes the local CLI override.

CI and production retain their `/app` layout. Rootless Docker and the existing
UID/GID mapping remain required; no host file ownership changes are needed.
