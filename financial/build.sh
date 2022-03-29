#!/bin/bash

############################################################################
# A script to build Token Handler resources for the financial-grade scenario
############################################################################

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
git clone https://github.com/curityio/oauth-agent-kotlin-spring-fapi oauth-agent
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the OAuth Agent"
  exit 1
fi

cd oauth-agent
./gradlew bootJar
if [ $? -ne 0 ]; then
  echo "Problem encountered building the OAuth Agent's Java code"
  exit 1
fi

docker build -f Dockerfile -t oauthagent-financial:1.0.0 .
if [ $? -ne 0 ]; then
  echo "Problem encountered building the OAuth Agent Docker file"
  exit 1
fi

#
# Get the OAuth Proxy, which runs within an NGINX based reverse proxy
#
cd ..
rm -rf oauth-proxy-plugin
git clone https://github.com/curityio/nginx-lua-oauth-proxy-plugin oauth-proxy-plugin
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the OAuth proxy plugin"
  exit 1
fi

#
# Also download the phantom token plugin for the reverse proxy
#
rm -rf kong-phantom-token-plugin
git clone https://github.com/curityio/kong-phantom-token-plugin
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the phantom token plugin"
  exit 1
fi
