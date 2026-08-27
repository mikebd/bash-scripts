# Requirement helpers

`requirements.sh` is a portable, sourceable library for shell workflows that
need to check command availability before use. It supports Bash 3.2 on macOS
and common GNU/Linux environments.

Source it from a repository-local script or adapter:

```bash
shared_scripts_root="${MIKEBD_BASH_SCRIPTS_ROOT:-$HOME/src/mikebd/bash/scripts}"
source "$shared_scripts_root/lib/requirements.sh"
```

It provides:

- `mikebd_require_command <command> [hint]`, which returns success when the
  command is available. Otherwise it writes an error, optionally writes the
  supplied installation hint, and returns failure.
- `mikebd_require_git`, the Git-specific wrapper used by shared Git helpers.

Sourcing the library only defines its namespaced functions; it does not change
the caller's shell options, variables, or traps.
