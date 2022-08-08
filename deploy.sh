#!/bin/bash

######################################################################
# A script to deploy Token Handler resources for the standard scenario
######################################################################

#
# Ensure that we are in the folder containing this script
#
cd "$(dirname "${BASH_SOURCE[0]}")"

#
# Check for a license file
#
if [ ! -f './components/idsvr/license.json' ]; then
  echo "Please provide a license.json file in the components/idsvr folder in order to deploy the system"
  exit 1
fi

#
# Check that helper tools are installed
#
jq -V 1>/dev/null
if [ $? -ne 0 ]; then
  echo "Problem encountered running the jq command: please ensure that this tool is installed"
  exit 1
fi
envsubst -V 1>/dev/null
if [ $? -ne 0 ]; then
  echo "Problem encountered running the envsubst command: please ensure that this tool is installed"
  exit 1
fi
openssl version 1>/dev/null
if [ $? -ne 0 ]; then
  echo "Problem encountered running the openssl command: please ensure that this tool is installed"
  exit 1
fi

#
# Get the scenario to deploy and set some variables
#
if [ "$1" == 'financial' ]; then
  SCENARIO='financial'
  DOCKER_COMPOSE_FILE='docker-compose-financial.yml'
  SCHEME='https'
  SSL_CERT_FILE_PATH='./certs/example.server.p12'
  SSL_CERT_PASSWORD='Password1'
  NGINX_TEMPLATE_FILE_NAME='default.conf.financial.template'
else
  SCENARIO='standard'
  DOCKER_COMPOSE_FILE='docker-compose-standard.yml'
  SCHEME='http'
  SSL_CERT_FILE_PATH=''
  SSL_CERT_PASSWORD=''
  NGINX_TEMPLATE_FILE_NAME='default.conf.standard.template'
fi

#
# Different reverse proxies use different plugins and configuration techniques
#
if [ "$2" == 'nginx' ]; then
  REVERSE_PROXY_PROFILE='NGINX'
elif [ "$2" == 'openresty' ]; then
  REVERSE_PROXY_PROFILE='OPENRESTY'
else
  REVERSE_PROXY_PROFILE='KONG'
fi

#
# These variables are passed in from the parent deploy.sh script in the spa-using-token-handler repo
# When not supplied, set default values so that this repo can be run in isolation
#
if [ "$BASE_DOMAIN" == "" ]; then
  BASE_DOMAIN='example.com'
  WEB_SUBDOMAIN='www'
fi
if [ "$API_SUBDOMAIN" == "" ]; then
  API_SUBDOMAIN='api'
fi
if [ "$IDSVR_SUBDOMAIN" == "" ] && [ "$EXTERNAL_IDSVR_ISSUER_URI" == "" ]; then
  IDSVR_SUBDOMAIN='login'
fi

#
# Check that the parent build script has been run at least once, so that application level containers are available
#
if [ "$(docker images -q webhost:1.0.0)" == '' ]; then
  echo 'The Docker image for webhost was not found - please ensure that you have run the build.sh script from the spa-using-token-handler repo'
  exit 1
fi
if [ "$(docker images -q business-api:1.0.0)" == '' ]; then
  echo 'The Docker image for business-api was not found - please ensure that you have run the build.sh script from the spa-using-token-handler repo'
  exit 1
fi

#
# Set final domain details
#
WEB_DOMAIN=$BASE_DOMAIN
if [ "$WEB_SUBDOMAIN" != "" ]; then
  WEB_DOMAIN="$WEB_SUBDOMAIN.$BASE_DOMAIN"
fi
API_DOMAIN="$API_SUBDOMAIN.$BASE_DOMAIN"
IDSVR_DOMAIN="$IDSVR_SUBDOMAIN.$BASE_DOMAIN"
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
  HTTP_STATUS=$(curl -k -s "$EXTERNAL_IDSVR_ISSUER_URI/.well-known/openid-configuration" -o metadata.json -w '%{http_code}')
  if [ "$HTTP_STATUS" != '200' ]; then
    echo "Problem encountered downloading metadata from external Identity Server: $HTTP_STATUS"
    exit 1
  fi

  # Read endpoints
  METADATA=$(cat metadata.json)
  ISSUER_URI="$EXTERNAL_IDSVR_ISSUER_URI"
  AUTHORIZE_ENDPOINT=$(jq -r .authorization_endpoint <<< "$METADATA")
  AUTHORIZE_INTERNAL_ENDPOINT=$AUTHORIZE_ENDPOINT
  TOKEN_ENDPOINT=$(jq -r .token_endpoint <<< "$METADATA")
  USERINFO_ENDPOINT=$(jq -r .userinfo_endpoint <<< "$METADATA")
  INTROSPECTION_ENDPOINT=$(jq -r .introspection_endpoint <<< "$METADATA")
  JWKS_ENDPOINT=$(jq -r .jwks_uri <<< "$METADATA")
  LOGOUT_ENDPOINT=$(jq -r .end_session_endpoint <<< "$METADATA")

else

  # Deploy a Docker based identity server
  IDSVR_BASE_URL="$SCHEME://$IDSVR_SUBDOMAIN.$BASE_DOMAIN:8443"
  IDSVR_INTERNAL_BASE_URL="$SCHEME://login-$INTERNAL_DOMAIN:8443"
  IDSVR_PROFILE='WITH_IDSVR'

  # Use Docker standard endpoints
  ISSUER_URI="$IDSVR_BASE_URL/oauth/v2/oauth-anonymous"
  AUTHORIZE_ENDPOINT="$IDSVR_BASE_URL/oauth/v2/oauth-authorize"
  AUTHORIZE_INTERNAL_ENDPOINT="$IDSVR_INTERNAL_BASE_URL/oauth/v2/oauth-authorize"
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
export SCHEME
export BASE_DOMAIN
export WEB_DOMAIN
export API_DOMAIN
export IDSVR_DOMAIN
export INTERNAL_DOMAIN
export IDSVR_BASE_URL
export IDSVR_INTERNAL_BASE_URL
export ISSUER_URI
export AUTHORIZE_ENDPOINT
export AUTHORIZE_INTERNAL_ENDPOINT
export TOKEN_ENDPOINT
export USERINFO_ENDPOINT
export INTROSPECTION_ENDPOINT
export JWKS_ENDPOINT
export LOGOUT_ENDPOINT
export ENCRYPTION_KEY
export SSL_CERT_FILE_PATH
export SSL_CERT_PASSWORD

#
# Update template files with the encryption key and other supplied environment variables
#
cd components
envsubst < ./spa/config-template.json     > ./spa/config.json
envsubst < ./webhost/config-template.json > ./webhost/config.json
envsubst < ./api/config-template.json     > ./api/config.json
cd ..

#
# Create certificates when deploying the financial grade scenario
# Also set a variable passed through to components/idsvr/config-backup-financial.xml
#
if [ "$SCENARIO" == 'financial' ]; then

  if [ ! -f './certs/example.ca.pem' ]; then
    ./certs/create-certs.sh
    if [ $? -ne 0 ]; then
      echo "Problem encountered creating and installing certificates"
      exit 1
    fi
  fi
  export FINANCIAL_GRADE_CLIENT_CA=$(openssl base64 -in './certs/example.ca.pem' | tr -d '\n')
fi

#
# Update the reverse proxy configuration with runtime values, including the cookie encryption key
#
cd components/reverse-proxy
if [ "$REVERSE_PROXY_PROFILE" == 'NGINX' ]; then

  # Use NGINX if specified on the command line
  envsubst < "./nginx/$NGINX_TEMPLATE_FILE_NAME" | sed -e 's/§/$/g' > ./nginx/default.conf

elif [ "$REVERSE_PROXY_PROFILE" == 'OPENRESTY' ]; then

  # Use OpenResty if specified on the command line
  envsubst < "./openresty/$NGINX_TEMPLATE_FILE_NAME" > ./openresty/default.conf

else
  
  # Use Kong otherwise
  envsubst < ./kong/kong-template.yml > ./kong/kong.yml
fi
cd ../..

#
# Spin up all containers, using the Docker Compose file, which applies the deployed configuration
#
echo "Deploying resources for the $SCENARIO scenario using $REVERSE_PROXY_PROFILE reverse proxy ..."
docker compose --project-name spa down
docker compose --file $DOCKER_COMPOSE_FILE --profile $IDSVR_PROFILE --profile $REVERSE_PROXY_PROFILE --project-name spa up --detach
if [ $? -ne 0 ]; then
  echo "Problem encountered starting Docker components"
  exit 1
fi

#
# Configure Identity Server certificates when deploying the financial grade scenario
#
if [ "$SCENARIO" == 'financial' ]; then
  ./deploy-idsvr-certs.sh
fi

