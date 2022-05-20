#!/bin/bash

######################################################################
# A script to deploy Token Handler resources for the standard scenario
######################################################################

#
# Ensure that we are in the folder containing this script
#
cd "$(dirname "${BASH_SOURCE[0]}")"

#
# First check prerequisites
#
if [ ! -f './idsvr/license.json' ]; then
  echo "Please provide a license.json file in the standard/idsvr folder in order to deploy the system"
  exit 1
fi

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

#
# TODO: delete after testing
#
export BASE_DOMAIN='example.com'
export WEB_SUBDOMAIN='www'
export API_SUBDOMAIN='api'
export IDSVR_SUBDOMAIN='login'

#
# Basic sanity checks
#
if [ "$BASE_DOMAIN" == "" ]; then
  echo "No BASE_DOMAIN environment variable was supplied"
  exit 1
fi
if [ "$API_SUBDOMAIN" == "" ]; then
  echo "No API_SUBDOMAIN environment variable was supplied"
  exit 1
fi
if [ "$IDSVR_SUBDOMAIN" == "" ] && [ "$EXTERNAL_IDSVR_ISSUER_URI" == "" ]; then
  echo "No identity server domain was supplied in an environment variable"
  exit 1
fi

#
# Set default domain details
#
WEB_DOMAIN=$BASE_DOMAIN
if [ "$WEB_SUBDOMAIN" != "" ]; then
  WEB_DOMAIN="$WEB_SUBDOMAIN.$BASE_DOMAIN"
fi
API_DOMAIN="$API_SUBDOMAIN.$BASE_DOMAIN"
INTERNAL_DOMAIN="internal.$BASE_DOMAIN"

#
# Get OAuth related values as environment variables
#
if [ "$EXTERNAL_IDSVR_ISSUER_URI" != "" ]; then

  # Point to an external identity provider if required
  IDSVR_BASE_URL="$(echo $EXTERNAL_IDSVR_ISSUER_URI | cut -d/ -f1-3)"
  IDSVR_INTERNAL_BASE_URL="$IDSVR_BASE_URL"
  IDSVR_PROFILE='WITHOUT_IDSVR'

  # Get the data
  HTTP_STATUS=$(curl -k -s "$EXTERNAL_IDSVR_ISSUER_URI/.well-known/openid-configuration" \
    -o metadata.json -w '%{http_code}')
  if [ "$HTTP_STATUS" != '200' ]; then
    echo "Problem encountered downloading metadata from external Identity Server: $HTTP_STATUS"
    exit 1
  fi

  # Read endpoints
  METADATA=$(cat metadata.json)
  AUTHORIZE_ENDPOINT=$(jq -r .authorization_endpoint <<< "$METADATA")
  TOKEN_ENDPOINT=$(jq -r .token_endpoint <<< "$METADATA")
  USERINFO_ENDPOINT=$(jq -r .userinfo_endpoint <<< "$METADATA")
  INTROSPECTION_ENDPOINT=$(jq -r .introspection_endpoint <<< "$METADATA")
  JWKS_ENDPOINT=$(jq -r .jwks_uri <<< "$METADATA")
  LOGOUT_ENDPOINT=$(jq -r .end_session_endpoint <<< "$METADATA")

else

  # Deploy a Docker based identity server
  IDSVR_BASE_URL="http://$IDSVR_SUBDOMAIN.$BASE_DOMAIN:8443"
  IDSVR_INTERNAL_BASE_URL="http://login-$INTERNAL_DOMAIN:8443"
  IDSVR_PROFILE='WITH_IDSVR'

  # Use Docker standard endpoints
  AUTHORIZE_ENDPOINT="$IDSVR_BASE_URL/oauth/v2/oauth-authorize"
  TOKEN_ENDPOINT="$IDSVR_INTERNAL_BASE_URL/oauth/v2/oauth-token"
  USERINFO_ENDPOINT="$IDSVR_INTERNAL_BASE_URL/oauth/v2/oauth-userinfo"
  INTROSPECTION_ENDPOINT="${IDSVR_INTERNAL_BASE_URL}/oauth/v2/oauth-introspect"
  JWKS_ENDPOINT="${IDSVR_INTERNAL_BASE_URL}/oauth/v2/oauth-anonymous/jwks"
  LOGOUT_ENDPOINT="${IDSVR_BASE_URL}/oauth/v2/oauth-session/logout"
fi

#
# Supply the 32 byte encryption key for AES256 as an environment variable
#
ENCRYPTION_KEY=$(openssl rand 32 | xxd -p -c 64)
echo -n $ENCRYPTION_KEY > encryption.key

#
# Export variables needed for substitution and deployment
#
export BASE_DOMAIN
export WEB_DOMAIN
export API_DOMAIN
export INTERNAL_DOMAIN
export IDSVR_BASE_URL
export IDSVR_INTERNAL_BASE_URL
export AUTHORIZE_ENDPOINT
export TOKEN_ENDPOINT
export USERINFO_ENDPOINT
export INTROSPECTION_ENDPOINT
export JWKS_ENDPOINT
export LOGOUT_ENDPOINT
export ENCRYPTION_KEY

#
# Update template files with the encryption key and other supplied environment variables
#
envsubst < ./spa/config-template.json     > ./spa/config.json
envsubst < ./webhost/config-template.json > ./webhost/config.json
envsubst < ./api/config-template.json     > ./api/config.json

#
# Update the reverse proxy configuration with runtime values such as the encryption key
#
if [ "$REVERSE_PROXY_PROFILE" == 'NGINX' ]; then

  # Use NGINX if specified on the command line
  envsubst < ./reverse-proxy/nginx/default.conf.template | sed -e 's/§/$/g' > ./reverse-proxy/nginx/default.conf

elif [ "$REVERSE_PROXY_PROFILE" == 'OPENRESTY' ]; then

  # Use OpenResty if specified on the command line
  envsubst < ./reverse-proxy/openresty/default.conf.template > ./reverse-proxy/openresty/default.conf

else
  
  # Use Kong by default
  envsubst < ./reverse-proxy/kong/kong-template.yml > ./reverse-proxy/kong/kong.yml
fi

#
# Spin up all containers, using the Docker Compose file, which applies the deployed configuration
#
docker compose --project-name spa down
docker compose --profile $IDSVR_PROFILE --profile $REVERSE_PROXY_PROFILE --project-name spa up --detach
if [ $? -ne 0 ]; then
  echo "Problem encountered starting Docker components"
  exit 1
fi
