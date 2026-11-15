#!/usr/bin/env bash
set -euo pipefail

image="${1:?Usage: bash .github/scripts/production_smoke.sh IMAGE}"
container_id=

cleanup() {
  local result=$?
  if [[ -n "$container_id" ]]; then
    docker logs "$container_id" || true
    docker rm --force "$container_id" >/dev/null || true
  fi
  exit "$result"
}
trap cleanup EXIT

# Keep the image's normal CMD and user. Test mode skips Google credentials;
# loopback HTTP still exercises the real server with external networking disabled.
container_id="$(docker run --detach --network none -e APP_ENV=test "$image")"

docker exec "$container_id" bundle exec ruby -rnet/http -rjson -e '
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
  begin
    response = Net::HTTP.start("127.0.0.1", 4567, open_timeout: 1, read_timeout: 2) do |http|
      http.get("/health")
    end
  rescue Errno::ECONNREFUSED
    abort "Server did not listen within 30 seconds" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
    sleep 0.5
    retry
  end
  abort "Unexpected health response: #{response.code} #{response.body}" unless
    response.code == "200" && JSON.parse(response.body).fetch("status") == "ok"
  puts response.body
'

# Confirm which server handled HTTP, rather than accepting a fallback handler.
docker logs "$container_id" 2>&1 | grep -F 'Puma starting'

docker stop --timeout 10 "$container_id" >/dev/null
exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container_id")"
case "$exit_code" in
  0|143) ;; # Sinatra may propagate SIGTERM as 128 + 15; SIGKILL (137) must fail.
  *)
    echo "Server did not stop cleanly (exit code $exit_code)" >&2
    exit 1
    ;;
esac

echo "Puma HTTP and shutdown smoke test passed"
