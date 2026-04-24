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
# Firewall: default-deny outbound traffic. Allow only what is required:
# - loopback traffic (OpenCode -> local squid)
# - established/related packets
# - squid process (proxy user) DNS + HTTP/HTTPS to the internet
# ---------------------------------------------------------------------------
echo ">> configuring firewall"
iptables -P OUTPUT DROP

# Allow loopback (needed for proxy connections to squid on 127.0.0.1:3128)
iptables -A OUTPUT -o lo -j ACCEPT
# Allow packets that belong to already established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow squid process DNS lookups
iptables -A OUTPUT -m owner --uid-owner proxy -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 53 -j ACCEPT
# Allow squid process outbound HTTP / HTTPS
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 443 -j ACCEPT

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

if [[ -f /workspace/opencode-sandbox.env ]]; then
  echo ">> loading environment from opencode-sandbox.env"
  set -o allexport
  # shellcheck source=/dev/null
  source /workspace/opencode-sandbox.env
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
