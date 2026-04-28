# opencode-sandbox

OpenCode is a powerful AI coding assistant — but by default it runs on your host machine with broad access to your environment, shared session state, and a single global configuration for all projects.

**opencode-sandbox** runs OpenCode inside a Docker container, giving each project its own isolated environment:

- 🔒 **Scoped access** — OpenCode can only see the project workspace, nothing else on your machine
- 🧩 **Per-project configuration** — AI providers, API keys, and model settings are configured independently per project
- 💾 **Persistent session state** — each project retains its own OpenCode history and session between container restarts
- 🧹 **Clean environment** — no bleed-over between projects; rebuild any time for a fresh start

opencode-sandbox uses [mise](https://mise.jdx.dev/) to manage software inside the container. **mise does not need to be installed on your host machine**, though using it on the host as well is recommended for a consistent toolchain experience.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
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

This will interactively create `mise.toml`, `opencode-sandbox-config.yaml`, `opencode.jsonc`, update `.gitignore`, and build the container — confirming each step before acting.

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
2. `opencode-sandbox-config.yaml` — YAML config controlling outbound HTTP/HTTPS whitelist, host TCP ports, and env var passthrough
3. `opencode.jsonc` — OpenCode model, provider, and permission config
4. `.gitignore` entries for `.opencode-sandbox/`
5. Builds the Docker container image

### `ocs-rebuild-container`

Prepares build artifacts and rebuilds the Docker image. Run this whenever you want a fresh image (new password, updated `mise.toml`, updated `opencode-sandbox-config.yaml`, etc.).

- Derives a container name from your project directory (e.g. `opencode-my-project`)
- Generates a random server password saved to `.opencode-sandbox/opencode-password` with owner-only permissions
- Copies `mise.toml` into the build context
- Parses `opencode-sandbox-config.yaml` into derived build artifacts
- Builds the Docker image

### `ocs-start-container`

Starts the sandbox for the current project.

- Resumes the existing container if it was previously stopped (state is preserved)
- Creates a fresh container on first run
- Forwards whitelisted host environment variables into the container (as configured in `opencode-sandbox-config.yaml`)
- Mounts your project root as `/workspace` inside the container
- Exposes OpenCode on `http://127.0.0.1:4096`
- Press `Ctrl+C` to stop the container

### `ocs-web`

Opens `http://127.0.0.1:4096` in your default browser on macOS or Linux.

Use `ocs-web-auth` for authentication or authenticate manually in the browser when prompted:

- **Username:** `opencode`
- **Password:** contents of `.opencode-sandbox/opencode-password` in your project root


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
| Stop the container | `Ctrl+C` in the `ocs-start-container` terminal |

> **Note:** The container is not removed on stop — state is preserved between sessions. `ocs-rebuild-container` will remove the old container before building a new image.

---

## Network isolation (firewall)

The container runs an internal [Squid](https://www.squid-cache.org/) proxy that restricts outbound HTTP/HTTPS traffic to an explicit whitelist. `iptables` rules inside the container use a default-deny outbound policy and allow only loopback traffic, established connections, and Squid's own DNS + HTTP/HTTPS egress. OpenCode (and any tools it spawns) must go through the proxy.

All outbound traffic is routed via the proxy automatically through the standard `http_proxy` / `https_proxy` environment variables set by the container entrypoint.

### Configuring the sandbox

The `opencode-sandbox-config.yaml` file in your project root is a YAML file with four top-level keys. Lines starting with `#` are comments.

> **Note:** Only a narrow YAML subset is supported: top-level section keys, one-level-deep list items (`- value`), and one-level-deep map entries (`key: value`). Anchors, multi-line strings, nested structures, and other YAML features are not supported.

```yaml
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
```

**`http-domain-whitelist`** — domains allowed through the Squid HTTP/HTTPS proxy:
- A leading dot matches the domain **and** all its subdomains (e.g. `.github.com` allows `github.com`, `api.github.com`, `raw.githubusercontent.com`, etc.)
- Without a leading dot, only the exact domain is matched (e.g. `api.anthropic.com` does **not** allow `bedrock.anthropic.com`)
- When in doubt, use the leading-dot form to avoid hard-to-debug connection failures
- Used for AI providers, package registries, and any other HTTP/HTTPS endpoints

**`host-ports`** — TCP ports on the host machine the container may connect to directly (bypasses the proxy):
- Use this for databases and other non-HTTP services running on the host or in another Docker container
- The host is reachable via `docker.host` (injected automatically at container start)

**`env-passthrough`** — host environment variable names to forward into the container:
- Variables not set in the host environment are silently skipped
- This avoids storing secrets in files — keep secrets in your shell environment (e.g. via your shell profile or a secret manager)
- Format is always `CONTAINER_NAME: HOST_NAME` — use the same name on both sides for a simple passthrough, or different names to rename
- A rebuild is required after adding or removing entries

**`env`** — static `KEY: VALUE` environment variables set directly in the container:
- Use this for non-secret project context that is safe to commit: repo name, project identifiers, feature flags, etc.
- Values are literal — no shell expansion
- A rebuild is required after adding or removing entries

`ocs-rebuild-container` reads this file to generate derived build artifacts — **a rebuild is required after changes**. The file is required (`ocs-init` creates it from a template); `ocs-rebuild-container` fails if it is missing.

> **Note:** The container requires the `NET_ADMIN` Docker capability for `iptables` — this is added automatically by `ocs-start-container`.

---

## Environment variables

Environment variables are forwarded into the container in two ways, both configured in `opencode-sandbox-config.yaml`.

### Static variables — `[env]` section

For non-secret project context that is safe to commit:

```yaml
env:
  GITHUB_REPOSITORY: my-org/my-repo
  PROJECT_ENV: development
```

Values are literal `KEY=VALUE` pairs passed directly to the container. Requires a rebuild after changes.

### Secret variables — `[env-passthrough]` section

For secrets and credentials that must not be stored in files:

```yaml
env-passthrough:
  ANTHROPIC_API_KEY: ANTHROPIC_API_KEY
  OPENAI_API_KEY: OPENAI_API_KEY
  GH_TOKEN: MY_PROJECT_GH_TOKEN
```

Only the variable *names* (and optional rename mapping) are listed in the config file. Values are read from the host environment at container start time:

```bash
export ANTHROPIC_API_KEY=sk-...
export MY_PROJECT_GH_TOKEN=ghp_...
ocs-start-container
```

Or add them to your shell profile (`.zshrc`, `.bashrc`, etc.) for permanent availability. Variables not set in the host environment are silently skipped. Requires a rebuild after adding or removing names.

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

Each project gets its own isolated container named after the project directory (e.g. `opencode-my-project`). State is stored in `.opencode-sandbox/` at the project root:

```
.opencode-sandbox/
├── container-name        # Locked container name for this project
├── opencode-password     # Generated server password (created with owner-only permissions)
├── mise.toml             # Copied from project root at build time
├── squid.conf            # Copied from opencode-sandbox repo at build time
├── squid-whitelist.txt       # Extracted from [http-domain-whitelist] section at build time
├── host-ports.txt            # Extracted from [host-ports] section at build time
├── env-passthrough.txt       # Extracted from [env-passthrough] section at build time
├── env.txt                   # Extracted from [env] section at build time
├── docker-build.log      # Docker build output (created during build)
└── opencode-state/       # Persistent OpenCode state (mounted into the container)
```

OpenCode state (including session history, configuration, and cache) is persisted across container restarts by mounting `.opencode-sandbox/opencode-state/` as `/home/dev/.local/share/opencode` inside the container.

Add `.opencode-sandbox/` to the sandboxed project's ignore rules so these generated files do not get committed.
