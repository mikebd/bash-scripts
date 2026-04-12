#!/usr/bin/env bash
set -euo pipefail

# Normalize clipboard text by stripping leading indentation from each line,
# joining wrapped lines into paragraphs, preserving blank-line breaks, and
# keeping list items and their indented continuation lines intact.
xclip -selection clipboard -o | awk '
function is_list_item(line) {
  return line ~ /^([-*+]|[0-9]+[.])([[:space:]]|$)/
}

function flush_paragraph() {
  if (in_paragraph) {
    printf "\n"
    in_paragraph = 0
  }
}

{
  raw_line = $0
  is_indented = raw_line ~ /^[[:space:]]+/
  line = raw_line
  sub(/^[[:space:]]+/, "", line)

  if (!length(line)) {
    flush_paragraph()
    if (!last_was_blank) {
      printf "\n"
    }
    in_list = 0
    last_was_blank = 1
    next
  }

  current_is_list_item = is_list_item(line)

  if (current_is_list_item) {
    flush_paragraph()
    printf "%s\n", line
    in_list = 1
    last_was_blank = 0
    next
  }

  if (in_list && is_indented) {
    printf "%s\n", raw_line
    last_was_blank = 0
    next
  }

  if (in_list) {
    printf "\n"
    in_list = 0
  }

  printf "%s%s", in_paragraph ? " " : "", line
  in_paragraph = 1
  last_was_blank = 0
}

END {
  if (in_paragraph) {
    printf "\n"
  }
}
' | {
  if command -v cb >/dev/null 2>&1; then
    cb
  else
    cat
  fi
}
