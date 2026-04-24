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
# - host TCP ports listed in /etc/host-ports.txt
# ---------------------------------------------------------------------------
echo ">> configuring firewall"
# Flush existing OUTPUT rules to avoid duplicates on container restart
iptables  -F OUTPUT
ip6tables -F OUTPUT

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
HOST_GW=$(ip route show default | awk '/default/ { print $3; exit }')
LIMA_HOST_IP=$(getent hosts host.lima.internal 2>/dev/null | awk '{print $1; exit}' || true)
CONTAINERS_HOST_IP=$(getent hosts host.containers.internal 2>/dev/null | awk '{print $1; exit}' || true)

# Collect unique IPs to allow (default gateway + known host aliases)
HOST_IPS=()
[[ -n "${HOST_GW}"            ]] && HOST_IPS+=("${HOST_GW}")
[[ -n "${LIMA_HOST_IP}"       && "${LIMA_HOST_IP}"       != "${HOST_GW}"       ]] && HOST_IPS+=("${LIMA_HOST_IP}")
[[ -n "${CONTAINERS_HOST_IP}" && "${CONTAINERS_HOST_IP}" != "${HOST_GW}"       \
                               && "${CONTAINERS_HOST_IP}" != "${LIMA_HOST_IP}"  ]] && HOST_IPS+=("${CONTAINERS_HOST_IP}")

# Resolve the canonical host IP: first of lima, containers, or gateway
HOST_IP="${LIMA_HOST_IP:-${CONTAINERS_HOST_IP:-${HOST_GW}}}"

# Add a single canonical alias so both runtimes work with one hostname
if [[ -n "${HOST_IP}" ]]; then
  echo "${HOST_IP}  docker.host" >> /etc/hosts
fi

for host_ip in "${HOST_IPS[@]}"; do
  while IFS= read -r port || [[ -n "${port}" ]]; do
    iptables -A OUTPUT -d "${host_ip}" -p tcp --dport "${port}" -j ACCEPT
  done < /etc/host-ports.txt
done

# ---------------------------------------------------------------------------
# Summary banner
# ---------------------------------------------------------------------------
echo ""
echo ">> sandbox configuration"
echo "   host alias:  docker.host -> ${HOST_IP:-<none>}"
echo ""
echo "   host ports (reachable via docker.host):"
while IFS= read -r port || [[ -n "${port}" ]]; do
  echo "     docker.host:${port}"
done < /etc/host-ports.txt
echo ""
echo "   https domains whitelisted:"
while IFS= read -r domain || [[ -n "${domain}" ]]; do
  echo "     ${domain}"
done < /etc/squid/squid-whitelist.txt
echo ""

# ---------------------------------------------------------------------------
# Environment: route outbound traffic through squid for all child processes
# ---------------------------------------------------------------------------
export http_proxy="http://127.0.0.1:3128"
export https_proxy="http://127.0.0.1:3128"
export HTTP_PROXY="http://127.0.0.1:3128"
export HTTPS_PROXY="http://127.0.0.1:3128"
_no_proxy_hosts="localhost,127.0.0.1,docker.host,host.lima.internal,host.docker.internal,host.containers.internal"
for host_ip in "${HOST_IPS[@]}"; do
  _no_proxy_hosts="${_no_proxy_hosts},${host_ip}"
done
export no_proxy="${_no_proxy_hosts}"
export NO_PROXY="${_no_proxy_hosts}"

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
