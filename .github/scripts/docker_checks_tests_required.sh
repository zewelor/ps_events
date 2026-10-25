#!/usr/bin/env bash
set -euo pipefail

has_changes=false

while IFS= read -r path || [[ -n "$path" ]]; do
  [[ -z "$path" ]] && continue
  has_changes=true

  case "$path" in
    AGENTS.md|README*|docs/*) ;;
    *)
      echo true
      exit 0
      ;;
  esac
done

# Fail safe when change detection returns no paths: do not skip verification.
if [[ "$has_changes" == true ]]; then
  echo false
else
  echo true
fi
