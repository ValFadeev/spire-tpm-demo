#! /bin/bash

docker exec spire-server \
  /opt/spire/bin/spire-server bundle show     \
  -socketPath /opt/spire/data/server/server.sock     \
  -format pem     \
  > bootstrap.crt
