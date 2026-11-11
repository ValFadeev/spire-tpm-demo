#! /bin/bash

docker exec spire-server \
  /opt/spire/bin/spire-server agent list \
  -socketPath /opt/spire/data/server/server.sock
