# AGENTS.md

## Scope

This repo contains small Bash-first utilities for local use.

- Prefer direct, simple solutions.
- Keep changes tightly scoped to the user's request.
- Do not perform drive-by cleanup, portability hardening, or broad refactors
  unless explicitly asked.

## AGENTS.md Updates

- When `AGENTS.md` is changed during a session, reread it before continuing so
  subsequent work follows the updated guidance.
- When asked to update `AGENTS.md`, propose concise wording that improves agent
  direction rather than just echoing the request verbatim.

## Shell Portability Expectations

This repo prefers Linux-specific simplicity over portable complexity.

This is a default, not a prohibition on explicitly scoped compatibility
contracts. A directory or script that declares a stricter target must meet and
test that target without extending the requirement to unrelated utilities.

- Default target environment is Pop!_OS / Ubuntu-based Linux.
- Prefer `#!/usr/bin/env bash` for Bash scripts unless a fixed Bash path is
  intentionally required.
- Do not spend scope making scripts broadly portable across macOS, BSD, or
  other environments unless the user explicitly asks for that.
- GNU-specific flags, Linux-only helpers, Docker-oriented assumptions,
  machine-local tool choices, and newer-Bash features are acceptable when they
  keep the script clearer or more direct for the intended environment.
- When editing scripts, optimize first for correctness, safety, and clarity in
  the primary local Linux environment.
- Do not introduce portability workarounds that materially complicate the
  script unless cross-platform support is part of the request.
- If a script has a notable environment assumption that could surprise a future
  user, document it briefly in the README or near the script entrypoint.
- Users on other operating systems should be treated as adaptation cases, not
  as the default compatibility target.
- `git/worktree-links.sh` and `codex/launcher/` are explicit exceptions: support
  Bash 3.2 on macOS and common GNU/Linux environments, prefer portable command
  forms, and guard GNU/BSD differences. Keep that contract scoped to those
  paths unless a new directory or script documents its own exception.

## Editing Expectations

- Favor readable shell over clever shell.
- If logic becomes non-trivial, repetitive, or difficult to review, consider
  moving it into a small helper script or into a better-fit language such as
  Python.
- Avoid embedding large inline `awk` or `python` programs when a named helper
  would be clearer.
- Preserve existing script behavior unless the requested task is to change it.

## Sourceable Shell Files

- `source` runs code in the caller's shell. Sourceable files must not assign
  generic top-level variables, define generic helper functions, or install
  traps that can overwrite caller state.
- Resolve initialization paths in a function-local variable. Prefix any
  deliberate caller-facing state and helper functions with the owning
  subsystem; document its ownership, reset behavior, and expected lifetime.
- Preserve an existing unprefixed function only when it is a documented
  compatibility interface. Direct executable scripts, not sourceable helpers,
  own process-level traps. Do not use `unset` to repair accidental leaks.

## Documentation And Comments

- Use permanent, present-tense wording in long-lived docs and comments.
- Add comments only for non-obvious behavior, safety-sensitive steps, or tricky
  command constructions.
- Avoid comments that merely restate the code.

## Validation

After editing shell scripts:

- Run `bash -n` on touched scripts.
- Run `shellcheck` when available.
- When practical, run a small-scope smoke test for the changed path.
- If a tool is unavailable or a script cannot be safely exercised, say so
  explicitly.
