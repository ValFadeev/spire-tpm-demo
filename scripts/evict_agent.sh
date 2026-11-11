#! /bin/bash

docker exec spire-server \
  /opt/spire/bin/spire-server agent evict     \
  -socketPath /opt/spire/data/server/server.sock     \
  -spiffeID "${1}"
