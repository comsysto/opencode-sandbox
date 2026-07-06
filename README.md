# opencode-sandbox

OpenCode is a powerful AI coding assistant — but by default it runs on your host machine with broad access to your environment, shared session state, and a single global configuration for all projects.

**opencode-sandbox** runs OpenCode inside a Docker container, giving each project its own isolated environment:

- 🔒 **Scoped access** — OpenCode can only see the project workspace, nothing else on your machine
- 🧩 **Per-project configuration** — AI providers, API keys, and model settings are configured independently per project
- 💾 **Persistent session state** — each project retains its own OpenCode history and session between container restarts
- 🧹 **Clean environment** — no bleed-over between projects; rebuild any time for a fresh start

opencode-sandbox uses [mise](https://mise.jdx.dev/) to manage software inside the container. **mise does not need to be installed on your host machine**, though using it on the host as well is recommended for a consistent toolchain experience.

---

## Compatibility

The following setups have been tested. Other combinations will most likely work too — if you try one, please [report your experience](https://github.com/comsysto/opencode-sandbox/issues).

| Host OS | Container Runtime | Status   |
|---------|-------------------|----------|
| macOS   | Colima            | ✅ Tested |
| macOS   | Podman            | ✅ Tested |
| Linux   | Docker            | ✅ Tested |

---

## Prerequisites

- A Docker-compatible container runtime (e.g. [Docker](https://docs.docker.com/get-docker/), [Podman](https://podman.io/), [Colima](https://colima.run/))
- [opencode](https://opencode.ai/) if you want to use opencode via a local terminal client instead of the web UI (optional, but recommended for a seamless experience)

---

## Installation

Clone this repository and add the `bin/` directory to your `PATH`:

```bash
git clone https://github.com/comsysto/opencode-sandbox.git
export PATH="/path/to/opencode-sandbox/bin:$PATH"
```

Add the `export` line to your shell profile (`.zshrc`, `.bashrc`, etc.) to make it permanent.

That's it — the `ocs-*` commands are now available globally.

---

## Project setup

Once installed, run the following from the **root of your project** to initialize and set up the sandbox:

```bash
ocs-init
```

This will interactively create `mise.toml`, `opencode-sandbox-config.yaml`, `opencode.jsonc`, `opencode-sandbox-pre-start-container.sh`, update `.gitignore`, and build the container — confirming each step before acting.

Then start it:

```bash
ocs-start-container
```

---

## Commands

`ocs-init` and `ocs-rebuild-container` must be run from the **project root**. All other commands can be run from the project root or any subdirectory inside the same project.

### `ocs-init`

Initializes a target project for use with opencode-sandbox. Run once from the project root.

Interactively creates (each step skipped if already present, default answer is yes):

1. `mise.toml` — minimal config with opencode only
2. `opencode-sandbox-config.yaml` — YAML config pre-filled with `sandbox-name` (set to the project directory name) and controls for outbound HTTP/HTTPS whitelist, host TCP ports, and env var passthrough
3. `opencode.jsonc` — OpenCode model, provider, and permission config
4. `opencode-sandbox-pre-start-container.sh` — empty hook script sourced before the container starts (see [Hooks](#hooks))
5. Builds the Docker container image

### `ocs-rebuild-container`

Prepares build artifacts and rebuilds the Docker image. Run this whenever you want a fresh image (new password, updated `mise.toml`, updated `opencode-sandbox-config.yaml`, etc.).

- Reads `sandbox-name` from `opencode-sandbox-config.yaml` and combines it with a short hash of the project root path to form a `SANDBOX_ID` (e.g. `my-project-a3f92c`), then names the container `opencode-sandbox-<SANDBOX_ID>`
- Creates `~/.opencode-sandbox/<SANDBOX_ID>/` for build artifacts and persistent state
- Generates a random server password saved to `~/.opencode-sandbox/<SANDBOX_ID>/opencode-password` with owner-only permissions
- Copies `mise.toml` into the build context
- Parses `opencode-sandbox-config.yaml` into derived build artifacts
- Builds the Docker image

### `ocs-start-container`

Starts the sandbox for the current project. Each invocation creates a fresh container (`--rm` ensures it is removed on stop); session state is preserved between runs because the workspace and OpenCode state are mounted volumes.

- Sources `opencode-sandbox-pre-start-container.sh` from the project root, if it exists (see [Hooks](#hooks))
- Forwards whitelisted host environment variables into the container (as configured in `opencode-sandbox-config.yaml`)
- Mounts your project root as `/<dirname>` inside the container (e.g. a project at `/home/user/my-project` is mounted at `/my-project`)
- Mounts any additional directories configured in the `volume-mounts` section of `opencode-sandbox-config.yaml`
- Exposes OpenCode on `http://127.0.0.1:4096`
- Press `Ctrl+C` to stop and remove the container

### `ocs-web`

Opens `http://127.0.0.1:4096` in your default browser on macOS or Linux.

Use `ocs-web-auth` for authentication or authenticate manually in the browser when prompted:

- **Username:** `opencode`
- **Password:** contents of `~/.opencode-sandbox/<SANDBOX_ID>/opencode-password`

### `ocs-web-auth`

Opens the browser with credentials embedded in the URL (basic auth) on macOS or Linux. Use this on first visit to authenticate your browser session.

> **Note:** After authenticating, the page may show a JavaScript error — this is expected. Your session is authenticated; use `ocs-web` to open a clean working tab.

### `ocs-terminal`

Attaches an OpenCode terminal session to the running container.

---

## Container lifecycle

| Situation | Command |
|---|---|
| First time setup | `ocs-init` then `ocs-start-container` |
| Daily use | `ocs-start-container` |
| After changing `mise.toml` | `ocs-rebuild-container` then `ocs-start-container` |
| After changing `opencode-sandbox-config.yaml` | `ocs-rebuild-container` then `ocs-start-container` |
| Stop the container | `Ctrl+C` in the `ocs-start-container` terminal (container is removed) |

> **Note:** Each `ocs-start-container` run creates a fresh container that is removed on stop. Session state is preserved between runs via mounted volumes (workspace and `~/.opencode-sandbox/<SANDBOX_ID>/opencode-state/`). `ocs-rebuild-container` rebuilds the image but does not affect the mounted state.

---

## Network isolation (firewall)

The container runs an internal [Squid](https://www.squid-cache.org/) proxy that restricts outbound HTTP/HTTPS traffic to an explicit whitelist. `iptables` rules inside the container use a default-deny outbound policy and allow only loopback traffic, established connections, and Squid's own DNS + HTTP/HTTPS egress. OpenCode (and any tools it spawns) must go through the proxy.

All outbound traffic is routed via the proxy automatically through the standard `http_proxy` / `https_proxy` environment variables set by the container entrypoint.

> **Note:** The container requires the `NET_ADMIN` Docker capability for `iptables` — this is added automatically by `ocs-start-container`.

---

## Configuration — `opencode-sandbox-config.yaml`

The `opencode-sandbox-config.yaml` file in your project root controls the project name, outbound network access, environment variables, and extra volume mounts. It is safe to commit.

> **Note:** Only a narrow YAML subset is supported: top-level keys, one-level-deep list items (`- value`), and one-level-deep map entries (`key: value`). Anchors, multi-line strings, nested structures, and other YAML features are not supported.

```yaml
sandbox-name: my-project

http-domain-whitelist:
  - .github.com
  - api.anthropic.com
  - registry.npmjs.org

host-ports:
  - 5432
  - 6379

env-passthrough:
  ANTHROPIC_API_KEY: ANTHROPIC_API_KEY
  GH_TOKEN: MY_PROJECT_GH_TOKEN

env:
  GITHUB_REPOSITORY: my-org/my-repo

volume-mounts:
  /shared-data: /home/user/shared-data

# docker-in-docker: true
```

**`sandbox-name`** — human-readable project identifier (required):
- Committed to the repository as a stable label for the project
- At runtime, combined with a short hash of the absolute project root path to form `SANDBOX_ID` (e.g. `my-project-a3f92c`), making collisions between multiple checkouts of the same repo unlikely
- `SANDBOX_ID` is used as the Docker image/container name (`opencode-sandbox-<SANDBOX_ID>`) and as the state directory name (`~/.opencode-sandbox/<SANDBOX_ID>/`)
- Set automatically by `ocs-init` using the directory basename
- You may rename it, but a rebuild is required and the old state directory in `~/.opencode-sandbox/` will be orphaned

**`http-domain-whitelist`** — domains allowed through the Squid HTTP/HTTPS proxy:
- A leading dot matches the domain **and** all its subdomains (e.g. `.github.com` allows `github.com`, `api.github.com`, `raw.githubusercontent.com`, etc.)
- Without a leading dot, only the exact domain is matched (e.g. `api.anthropic.com` does **not** allow `bedrock.anthropic.com`)
- When in doubt, use the leading-dot form to avoid hard-to-debug connection failures

**`host-ports`** — TCP ports on the host machine the container may connect to directly (bypasses the proxy):
- Use this for databases, local dev servers, and other services running on the host
- The host is reachable via `docker.host` (injected automatically at container start) — use this hostname instead of `localhost`

**`env-passthrough`** — host environment variables to forward into the container:
- Format is `CONTAINER_VAR: HOST_VAR` — use the same name on both sides for a simple passthrough, or different names to rename
- Values are read from the host shell at container start time; variables not set on the host are skipped and noted in the startup summary
- Use this for secrets and credentials — values never touch a file
- A rebuild is required after adding or removing entries

**`env`** — static environment variables set directly in the container:
- Use this for non-secret project context that is safe to commit: repo name, project identifiers, feature flags, etc.
- Values are literal — no shell expansion
- A rebuild is required after adding or removing entries

**`volume-mounts`** — additional host directories to mount into the container:
- Format is `CONTAINER_DIR: HOST_DIR` — both paths must be absolute
- Use this to give OpenCode access to directories outside the project root (e.g. shared data, local package caches, credential files)
- The host path is mounted read-write; use with care as OpenCode can modify the contents
- A rebuild is required after adding or removing entries

**`docker-in-docker`** — mount the host Docker socket into the container, allowing OpenCode to build and run containers:
- Set to `true` to enable; omit or set to `false` to disable
- When enabled, `/var/run/docker.sock` is automatically mounted into the container — no manual `volume-mounts` entry needed
- The container entrypoint dynamically creates a `docker` group matching the socket's GID at startup, so the `dev` user can access the socket regardless of host OS or runtime (Colima, Podman, Docker Desktop, etc.)
- A rebuild is required after changing this setting

```yaml
docker-in-docker: true
```

> **Note:** Enabling `docker-in-docker` only mounts the socket — it does not install Docker CLI tooling. You must add `docker` and/or `docker-compose` to your `mise.toml` so they are available inside the container (see [Docker-in-Docker setup](#docker-in-docker-setup) below).

`ocs-rebuild-container` reads this file to generate derived build artifacts — **a rebuild is required after changes**. The file is required; `ocs-rebuild-container` fails if it is missing.

---

## Docker-in-Docker setup

To let OpenCode build and run containers, you need two things:

1. **Socket access** — set `docker-in-docker: true` in `opencode-sandbox-config.yaml`
2. **CLI tooling** — install `docker` (CLI) and optionally `docker-compose` via `mise.toml`

### `opencode-sandbox-config.yaml`

```yaml
sandbox-name: my-project

docker-in-docker: true

http-domain-whitelist:
  - .github.com
  # ... other domains your project needs
```

### `mise.toml`

```toml
[tools]
"github:anomalyco/opencode" = "latest"

# Docker CLI — communicates with the host Docker daemon via the mounted socket
"aqua:docker/cli" = "latest"

# Docker Compose plugin (provides the `docker compose` subcommand)
"aqua:docker/compose" = "latest"
```

After updating `mise.toml`, rebuild the container:

```bash
ocs-rebuild-container
ocs-start-container
```

Once running, OpenCode can execute `docker` and `docker compose` commands that operate against the **host Docker daemon** — containers it starts are siblings on the host, not nested children. Keep this in mind when referencing mounted paths: paths must be valid on the **host**, not inside the sandbox container.

> **Example:** if your project is at `/home/user/my-project` on the host, bind-mount paths in `docker run -v` commands must use that host path, not the container-internal path `/<dirname>`.

---

## Hooks

### `opencode-sandbox-pre-start-container.sh`

If a file named `opencode-sandbox-pre-start-container.sh` exists in the project root, `ocs-start-container` will **source** it before starting the container. Because it is sourced (not executed as a subprocess), any `export` statements take effect in the calling shell and are picked up by `env-passthrough`.

Typical uses:
- Refresh short-lived credentials (AWS SSO, GCP, Azure, Vault, …)
- Derive env vars from the host at start time

`ocs-init` creates this file for you (empty, executable). If it contains secrets, add it to `.gitignore`:
```
opencode-sandbox-pre-start-container.sh
```

**Example — refresh AWS SSO credentials and forward them into the container:**

`opencode-sandbox-pre-start-container.sh`:
```bash
#!/usr/bin/env bash
aws sso login --profile my-profile
eval "$(aws configure export-credentials --profile my-profile --format env)"
```

`opencode-sandbox-config.yaml`:
```yaml
env-passthrough:
  AWS_ACCESS_KEY_ID: AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY: AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN: AWS_SESSION_TOKEN
```

---

## Project layout

```
opencode-sandbox/
├── bin/
│   ├── ocs-init                # Initialize a project for use with opencode-sandbox
│   ├── ocs-rebuild-container   # Build the Docker image
│   ├── ocs-start-container     # Start / resume the container
│   ├── ocs-terminal            # Attach a terminal session
│   ├── ocs-web                 # Open the web UI
│   └── ocs-web-auth            # Open the web UI with authentication
├── init-templates/             # Templates copied into target projects by ocs-init
├── shared                      # Shared configuration, utilities, and guards (sourced by bin scripts)
├── Dockerfile
├── entrypoint.sh
└── README.md
```

## Per-project state

Each project gets its own isolated container named `opencode-sandbox-<SANDBOX_ID>`. The `SANDBOX_ID` is derived at runtime from the `sandbox-name` in the config file and a short hash of the project root path, so multiple checkouts of the same repo get distinct IDs. State is stored in `~/.opencode-sandbox/<SANDBOX_ID>/` on the host:

```
~/.opencode-sandbox/
└── my-project-a3f92c/
    ├── opencode-password       # Generated server password (owner-only permissions)
    ├── mise.toml               # Copied from project root at build time
    ├── squid.conf              # Copied from opencode-sandbox repo at build time
    ├── squid-whitelist.txt     # Extracted from http-domain-whitelist at build time
    ├── host-ports.txt          # Extracted from host-ports at build time
    ├── env-passthrough.txt     # Extracted from env-passthrough at build time
    ├── env.txt                 # Extracted from env at build time
    ├── volume-mounts.txt       # Extracted from volume-mounts at build time
    ├── docker-build.log        # Docker build output (created during build)
    └── opencode-state/         # Persistent OpenCode state (mounted into the container)
```

OpenCode state (including session history, configuration, and cache) is persisted across container restarts by mounting `~/.opencode-sandbox/<SANDBOX_ID>/opencode-state/` as `/home/dev/.local/share/opencode` inside the container.

Aside from the initial project setup files that `ocs-init` copies into the project root, opencode-sandbox writes its runtime/build artifacts and persistent sandbox state under `~/.opencode-sandbox/<SANDBOX_ID>/`, not in the project directory — so no `.gitignore` entries are needed for sandbox state.

---

## Remarks

OpenCode Sandbox is not built by the OpenCode team and is not affiliated with OpenCode.
