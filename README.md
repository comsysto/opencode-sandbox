# opencode-sandbox

OpenCode is a powerful AI coding assistant — but by default it runs on your host machine with broad access to your environment, shared session state, and a single global configuration for all projects.

**ocs-sandbox** runs OpenCode inside a Docker container, giving each project its own isolated environment:

- 🔒 **Scoped access** — OpenCode can only see the project workspace, nothing else on your machine
- 🧩 **Per-project configuration** — AI providers, API keys, and model settings are configured independently per project
- 💾 **Persistent session state** — each project retains its own OpenCode history and session between container restarts
- 🧹 **Clean environment** — no bleed-over between projects; rebuild any time for a fresh start

ocs-sandbox uses [mise](https://mise.jdx.dev/) to manage software inside the container. **mise does not need to be installed on your host machine**, though using it on the host as well is recommended for a consistent toolchain experience.

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

Once installed, run the following from the **root of your project** (the directory containing `mise.toml`) to set up the sandbox for that project:

```bash
ocs-rebuild-container
```

Then start it:

```bash
ocs-start-container
```

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- A `mise.toml` file in the root of the project you want to sandbox

---

## Commands

All commands must be run from the **root of your project**.

### `ocs-rebuild-container`

Prepares build artifacts and builds the Docker image. Run this once initially and again whenever you want a fresh image (new password, updated `mise.toml`, etc.).

This will:
- Derive a container name from your project directory (e.g. `opencode-my-project`)
- Generate a random server password saved to `.opencode-sandbox/opencode-password`
- Copy `mise.toml` into the build context
- Build the Docker image

### `ocs-start-container`

Starts the sandbox for the current project.

- Resumes the existing container if it was previously stopped (state is preserved)
- Creates a fresh container on first run
- Mounts your project root as `/workspace` inside the container
- Exposes OpenCode on `http://127.0.0.1:4096`
- Press `Ctrl+C` to stop the container

### `ocs-web`

Opens `http://127.0.0.1:4096` in your default browser.

### `ocs-web-auth`

Opens the browser with credentials embedded in the URL (basic auth). Use this on first visit to authenticate your browser session.

### `ocs-terminal`

Attaches an OpenCode terminal session to the running container.

---

## Container lifecycle

| Situation | Command |
|---|---|
| First time setup | `ocs-rebuild-container` then `ocs-start-container` |
| Daily use | `ocs-start-container` |
| After changing `mise.toml` | `ocs-rebuild-container` then `ocs-start-container` |
| Stop the container | `Ctrl+C` in the `ocs-start-container` terminal |

> **Note:** The container is not removed on stop — state is preserved between sessions. `ocs-rebuild-container` will remove the old container before building a new image.

---

## Project layout

```
ocs-sandbox/
├── bin/
│   ├── ocs-rebuild-container   # Build the Docker image
│   ├── ocs-start-container     # Start / resume the container
│   ├── ocs-terminal            # Attach a terminal session
│   ├── ocs-web                 # Open the web UI
│   └── ocs-web-auth            # Open the web UI with authentication
├── config                      # Shared configuration (sourced by bin scripts)
├── Dockerfile
├── entrypoint.sh
└── README.md
```

## Per-project state

Each project gets its own isolated container named after the project directory (e.g. `opencode-my-project`). State is stored in `.opencode-sandbox/` at the project root (git-ignored):

```
.opencode-sandbox/
├── container-name      # Locked container name for this project
├── opencode-password   # Generated server password
└── mise.toml           # Copied from project root at build time
```


