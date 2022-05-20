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
# Different reverse proxies use different plugins and configuration techniques
#
if [ "$1" == 'nginx' ]; then
  REVERSE_PROXY_PROFILE='NGINX'
elif [ "$1" == 'openresty' ]; then
  REVERSE_PROXY_PROFILE='OPENRESTY'
else
  REVERSE_PROXY_PROFILE='KONG'
fi
echo "Building resources using $REVERSE_PROXY_PROFILE reverse proxy ..."

#
# Build the reverse proxy's custom dockerfile
#
if [ "$REVERSE_PROXY_PROFILE" == 'NGINX' ]; then

  # Use NGINX if specified on the command line
  cd reverse-proxy/nginx
  docker build --no-cache -f Dockerfile -t custom_nginx:1.21.3-alpine .
  if [ $? -ne 0 ]; then
    echo "Problem encountered building the NGINX Reverse Proxy Docker file"
    exit 1
  fi
  
  # Download modules
  cd reverse-proxy/openresty
  docker build --no-cache -f Dockerfile -t custom_openresty/openresty:1.19.9.1-2-bionic .
  if [ $? -ne 0 ]; then
    echo "Problem encountered building the OpenResty Reverse Proxy Docker file"
    exit 1
  fi

elif [ "$REVERSE_PROXY_PROFILE" == 'OPENRESTY' ]; then

  # Use OpenResty if specified on the command line
  cd reverse-proxy/openresty
  docker build --no-cache -f Dockerfile -t custom_openresty/openresty:1.19.9.1-2-bionic .
  if [ $? -ne 0 ]; then
    echo "Problem encountered building the OpenResty Reverse Proxy Docker file"
    exit 1
  fi

else
  
  # Use Kong by default
  cd reverse-proxy/kong
  docker build --no-cache -f Dockerfile -t custom_kong:2.6.0-alpine .
  if [ $? -ne 0 ]; then
    echo "Problem encountered building the Kong Reverse Proxy Docker file"
    exit 1
  fi
fi
cd ../..

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
