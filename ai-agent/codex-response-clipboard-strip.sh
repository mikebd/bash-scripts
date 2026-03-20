#!/usr/bin/env bash
set -euo pipefail

# Normalize clipboard text by stripping leading indentation from each line,
# joining wrapped lines into paragraphs, and preserving blank-line breaks.
xclip -selection clipboard -o | awk '
{
  sub(/^[[:space:]]+/, "")

  if (NF) {
    printf "%s%s", in_paragraph ? " " : "", $0
    in_paragraph = 1
  } else if (in_paragraph) {
    printf "\n\n"
    in_paragraph = 0
  }
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
