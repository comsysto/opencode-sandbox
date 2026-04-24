# AGENTS.md

See [README.md](README.md) for project overview, key files, commands, and per-project state layout.

README.md is intended for end users (developers setting up or using the sandbox). It may explain how things work internally, but must not document development practices — those belong here in AGENTS.md.

Every change to the user experience (new commands, changed behaviour, new files created in target projects, etc.) must be reflected in README.md.

## Lint (only CI-equivalent check)

```sh
shellcheck bin/* shared entrypoint.sh
```

No tests, no formatter, no typecheck, no CI workflows.

## Conventions

- All `bin/` scripts: `set -euo pipefail` + `source shared`
- After sourcing `shared`, re-assign `SCRIPT_DIR` if the script references other `bin/` scripts by path — `shared` overwrites `SCRIPT_DIR` with its own location
- `shared` provides: `find_sandbox_root` (walks up to `.opencode-sandbox/`), `use_sandbox_root`, `open_url`, `refresh_root_paths`
- `ocs-rebuild-container` must run from the **project root** (where `mise.toml` lives); all other `ocs-*` commands auto-detect root by walking up
- Container name is derived from project dir name: `opencode-<dirname>`
- Init templates (copied into target projects by `ocs-init`) live in `init-templates/`
