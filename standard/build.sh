#!/bin/bash

#####################################################################
# A script to build Token Handler resources for the standard scenario
#####1###############################################################

#
# Ensure that we are in the folder containing this script
#
cd "$(dirname "${BASH_SOURCE[0]}")"

#
# This is for Curity developers only
#
cp ../hooks/pre-commit ../.git/hooks

#
# Get and build the OAuth Agent
#
rm -rf oauth-agent
git clone https://github.com/curityio/oauth-agent-node-express oauth-agent
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the OAuth Agent"
  exit 1
fi
cd oauth-agent

npm install
if [ $? -ne 0 ]; then
  echo "Problem encountered installing the OAuth Agent dependencies"
  exit 1
fi

npm run build
if [ $? -ne 0 ]; then
  echo "Problem encountered building the OAuth Agent code"
  exit 1
fi

docker build -f Dockerfile -t oauthagent-standard:1.0.0 .
if [ $? -ne 0 ]; then
  echo "Problem encountered building the OAuth Agent Docker file"
  exit 1
fi
cd ..

#
# Build the reverse proxy's custom dockerfile
#
cd reverse-proxy
docker build -f Dockerfile -t custom_kong:2.6.0-alpine .
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the Kong OAuth Proxy Docker file"
  exit 1
fi
cd ..

#
# Also download the phantom token plugin for the reverse proxy
#
rm -rf kong-phantom-token-plugin
git clone https://github.com/curityio/kong-phantom-token-plugin
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the phantom token plugin"
  exit 1
fi
