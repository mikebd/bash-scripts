#!/usr/bin/env bash

# Print the active Branch Context directory tree when run from a .context
# directory, excluding lane-prefixed folders and the util directory.
[ "$(basename "$(pwd -P)")" = ".context" ] && \
for dir in [!_]*; do \
  [ -d "$dir" ] || continue; \
  [ "$dir" = "util" ] && continue; \
  printf '%s\n' "$dir"; \
done | \
xargs -r tree -d
