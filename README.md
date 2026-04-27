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

This will interactively create `mise.toml`, `opencode-sandbox.env`, `opencode-sandbox-firewall`, `opencode.jsonc`, update `.gitignore`, and build the container — confirming each step before acting.

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
2. `opencode-sandbox.env` — empty env file for project-specific variables
3. `opencode-sandbox-firewall` — section-based config controlling outbound HTTP/HTTPS whitelist and host TCP ports
4. `opencode.jsonc` — OpenCode model, provider, and permission config
5. `.gitignore` entries for `.opencode-sandbox/`, `opencode-sandbox.env`, and `opencode-sandbox-firewall`
6. Builds the Docker container image

### `ocs-rebuild-container`

Prepares build artifacts and rebuilds the Docker image. Run this whenever you want a fresh image (new password, updated `mise.toml`, etc.).

- Derives a container name from your project directory (e.g. `opencode-my-project`)
- Generates a random server password saved to `.opencode-sandbox/opencode-password` with owner-only permissions
- Copies `mise.toml` into the build context
- Builds the Docker image

### `ocs-start-container`

Starts the sandbox for the current project.

- Resumes the existing container if it was previously stopped (state is preserved)
- Creates a fresh container on first run
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
| Stop the container | `Ctrl+C` in the `ocs-start-container` terminal |

> **Note:** The container is not removed on stop — state is preserved between sessions. `ocs-rebuild-container` will remove the old container before building a new image.

---

## Network isolation (firewall)

The container runs an internal [Squid](https://www.squid-cache.org/) proxy that restricts outbound HTTP/HTTPS traffic to an explicit whitelist. `iptables` rules inside the container use a default-deny outbound policy and allow only loopback traffic, established connections, and Squid's own DNS + HTTP/HTTPS egress. OpenCode (and any tools it spawns) must go through the proxy.

All outbound traffic is routed via the proxy automatically through the standard `http_proxy` / `https_proxy` environment variables set by the container entrypoint.

### Configuring the firewall

The `opencode-sandbox-firewall` file in your project root uses a simple section-based format — a `[section]` header followed by one value per line. Lines starting with `#` are comments.

```
[http-domain-whitelist]
.github.com
api.anthropic.com
registry.npmjs.org

[host-ports]
5432
6379
```

**`[http-domain-whitelist]`** — domains allowed through the Squid HTTP/HTTPS proxy:
- A leading dot matches the domain **and** all its subdomains (e.g. `.github.com` allows `github.com`, `api.github.com`, `raw.githubusercontent.com`, etc.)
- Without a leading dot, only the exact domain is matched (e.g. `api.anthropic.com` does **not** allow `bedrock.anthropic.com`)
- When in doubt, use the leading-dot form to avoid hard-to-debug connection failures
- Used for AI providers, package registries, and any other HTTP/HTTPS endpoints

**`[host-ports]`** — TCP ports on the host machine the container may connect to directly (bypasses the proxy):
- Use this for databases and other non-HTTP services running on the host or in another Docker container
- The host is reachable via `docker.host` (injected automatically at container start)
- Pass the connection string via `opencode-sandbox.env` (e.g. `DATABASE_URL=postgres://user:pass@172.17.0.1:5432/mydb`)

`ocs-rebuild-container` reads this file to generate the derived `squid-whitelist.txt` and `host-ports.txt` files that are copied into the Docker build context — **a rebuild is required after changes**. The file is required (`ocs-init` creates it from a template); `ocs-rebuild-container` fails if it is missing.

> **Note:** The container requires the `NET_ADMIN` Docker capability for `iptables` — this is added automatically by `ocs-start-container`.

---

## Environment variables

Project-specific environment variables (e.g. API keys) can be passed to the container via `opencode-sandbox.env` in the project root:

```
ANTHROPIC_API_KEY=sk-...
GITHUB_TOKEN=ghp_...
```

- Plain `KEY=VALUE` format, one per line — no `export` needed
- The file is sourced by the container entrypoint before OpenCode starts, so all variables are automatically exported
- Takes effect without rebuilding the container — just restart with `ocs-start-container`
- Add `opencode-sandbox.env` to `.gitignore` if it contains secrets (`ocs-init` does this automatically)

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
├── opencode-sandbox-firewall # Copied from project root at build time (section-based format)
├── squid-whitelist.txt       # Extracted from [http-domain-whitelist] section at build time
├── host-ports.txt            # Extracted from [host-ports] section at build time
├── docker-build.log      # Docker build output (created during build)
└── opencode-state/       # Persistent OpenCode state (mounted into the container)
```

OpenCode state (including session history, configuration, and cache) is persisted across container restarts by mounting `.opencode-sandbox/opencode-state/` as `/home/dev/.local/share/opencode` inside the container.

Add `.opencode-sandbox/` to the sandboxed project's ignore rules so these generated files do not get committed.
