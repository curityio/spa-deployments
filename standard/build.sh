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
# Get and build the main Token Handler API (aka 'OAuth Agent')
#
rm -rf token-handler-api
git clone https://github.com/curityio/token-handler-node-express token-handler-api
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the token handler API"
  exit 1
fi

cd token-handler-api
npm install
if [ $? -ne 0 ]; then
  echo "Problem encountered installing the Token Handler API dependencies"
  exit 1
fi

npm run build
if [ $? -ne 0 ]; then
  echo "Problem encountered building the Token Handler API code"
  exit 1
fi

docker build -f Dockerfile -t token-handler-standard:1.0.0 .
if [ $? -ne 0 ]; then
  echo "Problem encountered building the Token Handler API Docker file"
  exit 1
fi

#
# Get the 'OAuth Proxy', which is a simple reverse proxy plugin
#
cd ..
rm -rf oauth-proxy-plugin
git clone https://github.com/curityio/nginx-lua-oauth-proxy-plugin oauth-proxy-plugin
if [ $? -ne 0 ]; then
  echo "Problem encountered downloading the OAuth proxy plugin"
  exit 1
fi

# TODO: delete on merge
cd oauth-proxy-plugin
git checkout feature/cors-refinements
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
