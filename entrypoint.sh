#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Proxy: start squid and wait until it is ready
# ---------------------------------------------------------------------------
echo ">> starting squid proxy (squid startup messages below are expected)"
squid
timeout 30 bash -c 'until curl --silent --output /dev/null --max-time 1 http://127.0.0.1:3128; do sleep 0.2; done'
echo ">> squid is ready"

# ---------------------------------------------------------------------------
# Firewall: default-deny outbound traffic. Allow only what is required:
# - loopback traffic (OpenCode -> local squid)
# - established/related packets
# - squid process (proxy user) DNS + HTTP/HTTPS to the internet
# - host TCP ports listed in /etc/host-ports.txt
# ---------------------------------------------------------------------------
echo ">> configuring firewall"
# Flush existing OUTPUT rules to avoid duplicates on container restart
iptables  -F OUTPUT
ip6tables -F OUTPUT
# Note: ip6tables is run unconditionally. On kernels without IPv6 support this will
# fail and abort startup. We accept this risk to keep the setup simple.

# Default-deny outbound for both IPv4 and IPv6
iptables  -P OUTPUT DROP
ip6tables -P OUTPUT DROP

# Allow loopback (needed for proxy connections to squid on 127.0.0.1:3128)
iptables  -A OUTPUT -o lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT
# Allow packets that belong to already established connections
iptables  -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow squid process DNS lookups
iptables  -A OUTPUT -m owner --uid-owner proxy -p udp --dport 53 -j ACCEPT
iptables  -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 53 -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p udp --dport 53 -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 53 -j ACCEPT
# Allow squid process outbound HTTP / HTTPS
iptables  -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 80  -j ACCEPT
iptables  -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 443 -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 80  -j ACCEPT
ip6tables -A OUTPUT -m owner --uid-owner proxy -p tcp --dport 443 -j ACCEPT

# Allow host TCP ports (databases etc.) — one port number per line in /etc/host-ports.txt
HOST_IP=$(getent hosts docker.host 2>/dev/null | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1; exit}' || true)

while IFS= read -r port || [[ -n "${port:-}" ]]; do
  iptables -A OUTPUT -d docker.host -p tcp --dport "${port}" -j ACCEPT
done < /etc/host-ports.txt

# ---------------------------------------------------------------------------
# Environment: route outbound traffic through squid for all child processes
# ---------------------------------------------------------------------------
export http_proxy="http://127.0.0.1:3128"
export https_proxy="http://127.0.0.1:3128"
export HTTP_PROXY="http://127.0.0.1:3128"
export HTTPS_PROXY="http://127.0.0.1:3128"
_no_proxy_hosts="localhost,127.0.0.1,docker.host"
[[ -n "${HOST_IP}" ]] && _no_proxy_hosts="${_no_proxy_hosts},${HOST_IP}"
export no_proxy="${_no_proxy_hosts}"
export NO_PROXY="${_no_proxy_hosts}"

# ---------------------------------------------------------------------------
# OpenCode credentials
# ---------------------------------------------------------------------------
OPENCODE_SERVER_PASSWORD=$(cat /opencode-password)
export OPENCODE_SERVER_PASSWORD
: "${OPENCODE_PORT:=4096}"
export OPENCODE_PORT

# ---------------------------------------------------------------------------
# Docker socket: match GID of mounted socket so dev user can access it
# ---------------------------------------------------------------------------
if [[ -S /var/run/docker.sock ]]; then
  DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
  if ! getent group "${DOCKER_GID}" > /dev/null 2>&1; then
    groupadd -g "${DOCKER_GID}" docker
  fi
  usermod -aG "${DOCKER_GID}" dev
fi

# ---------------------------------------------------------------------------
# Choose the user to run OpenCode as.
# Normally this is the unprivileged dev user (gosu drops root, env is inherited).
# With rootless Docker (or any user-namespace setup without keep-id) the host user is
# mapped to root inside the container, so dev cannot read the mounted project or write
# the state directory. In that case root *is* the host user, so run as root with the
# dev home directory instead.
# ---------------------------------------------------------------------------
echo ">> start opencode"
if gosu dev test -r "${WORKSPACE_DIR}/mise.toml" && gosu dev test -w /home/dev/.local/share/opencode; then
  RUN_AS=(gosu dev)
else
  echo "WARNING: user dev cannot access the mounted workspace/state (user namespace mapping or SELinux?)." >&2
  echo "         Falling back to running opencode as the container's root user (= your host user in rootless mode)." >&2
  export HOME=/home/dev
  RUN_AS=()
fi
# SC2016: single quotes are intentional — expressions must expand in the target user's shell, not this one
# shellcheck disable=SC2016
exec "${RUN_AS[@]+"${RUN_AS[@]}"}" bash -c '
  : "${WORKSPACE_DIR:?WORKSPACE_DIR is not set — was the container built without the WORKSPACE_DIR build arg?}"
  if [[ ! -r "${WORKSPACE_DIR}/mise.toml" ]]; then
    echo "ERROR: ${WORKSPACE_DIR}/mise.toml is not readable by user $(id -un) ($(id -u):$(id -g))." >&2
    exit 1
  fi
  mise trust --ignore "${WORKSPACE_DIR}/mise.toml"
  eval "$(mise activate --shell bash)"
  exec "$(mise where github:anomalyco/opencode)/opencode" web --mdns --port "${OPENCODE_PORT}"
'
