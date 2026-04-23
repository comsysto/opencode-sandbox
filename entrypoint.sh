#!/bin/bash

# ignore the file in the workspace as we already have installed everything via the global config in /etc/mise/config.toml
mise trust --ignore /workspace/mise.toml
eval $(mise activate --shell bash)

export OPENCODE_SERVER_PASSWORD=$(cat /opencode-password)
echo "OPENCODE_SERVER_PASSWORD=$OPENCODE_SERVER_PASSWORD"
exec $(mise where github:anomalyco/opencode)/opencode web --mdns