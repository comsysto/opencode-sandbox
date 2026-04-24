#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Proxy: start squid and wait until it is ready
# ---------------------------------------------------------------------------
echo ">> starting squid proxy"
squid

echo ">> waiting for squid to be ready on port 3128"
timeout 30 bash -c 'until echo >/dev/tcp/127.0.0.1/3128 2>/dev/null; do sleep 0.2; done'
echo ">> squid is ready"

# ---------------------------------------------------------------------------
# Firewall: block direct outbound HTTP/HTTPS; only squid (proxy user) may
# connect directly on those ports.  All other traffic (DNS, etc.) is allowed.
# ---------------------------------------------------------------------------
echo ">> configuring firewall"
# Allow loopback (needed for proxy connections to squid on 127.0.0.1:3128)
iptables -A OUTPUT -o lo -j ACCEPT
# Allow packets that belong to already established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Allow the squid process (runs as the 'proxy' OS user) to reach the internet
iptables -A OUTPUT -m owner --uid-owner proxy -j ACCEPT
# Block every other process from opening direct HTTP / HTTPS connections
iptables -A OUTPUT -p tcp --dport 80  -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -p tcp --dport 443 -j REJECT --reject-with tcp-reset

# ---------------------------------------------------------------------------
# Environment: route outbound traffic through squid for all child processes
# ---------------------------------------------------------------------------
export http_proxy="http://127.0.0.1:3128"
export https_proxy="http://127.0.0.1:3128"
export HTTP_PROXY="http://127.0.0.1:3128"
export HTTPS_PROXY="http://127.0.0.1:3128"
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

# ---------------------------------------------------------------------------
# OpenCode credentials and optional project env file
# ---------------------------------------------------------------------------
OPENCODE_SERVER_PASSWORD=$(cat /opencode-password)
export OPENCODE_SERVER_PASSWORD

if [[ -f /workspace/.opencode-sandbox.env ]]; then
  echo ">> loading environment from .opencode-sandbox.env"
  set -o allexport
  # shellcheck source=/dev/null
  source /workspace/.opencode-sandbox.env
  set +o allexport
fi

# ---------------------------------------------------------------------------
# Start OpenCode as the dev user (gosu drops root, env is inherited)
# ---------------------------------------------------------------------------
echo ">> start opencode"
# SC2016: single quotes are intentional — expressions must expand in the dev user's shell, not root's
# shellcheck disable=SC2016
exec gosu dev bash -c '
  mise trust --ignore /workspace/mise.toml
  eval "$(mise activate --shell bash)"
  exec "$(mise where github:anomalyco/opencode)/opencode" web --mdns
'
