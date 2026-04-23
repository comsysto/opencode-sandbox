#!/bin/bash

# ignore the file in the workspace as we already have installed everything via the global config in /etc/mise/config.toml
echo ">> preparing mise environment"
mise trust --ignore /workspace/mise.toml
eval "$(mise activate --shell bash)"

OPENCODE_SERVER_PASSWORD=$(cat /opencode-password)
export OPENCODE_SERVER_PASSWORD
echo ">> start opencode"
exec "$(mise where github:anomalyco/opencode)/opencode" web --mdns