#!/bin/bash

# ignore the file in the workspace as we already have installed everything via the global config in /etc/mise/config.toml
echo ">> preparing mise environment"
mise trust --ignore /workspace/mise.toml
eval "$(mise activate --shell bash)"

OPENCODE_SERVER_PASSWORD=$(cat /opencode-password)
export OPENCODE_SERVER_PASSWORD

if [[ -f /workspace/.opencode-sandbox.env ]]; then
  echo ">> loading environment from .opencode-sandbox.env"
  set -o allexport
  # shellcheck source=/dev/null
  source /workspace/.opencode-sandbox.env
  set +o allexport
fi

echo ">> start opencode"
exec "$(mise where github:anomalyco/opencode)/opencode" web --mdns