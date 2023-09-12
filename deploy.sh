#!/bin/bash

########################################################################
# A script to deploy Token Handler resources in a Docker compose network
# A number of deployment variations are supported by this script
########################################################################

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
# Get platform specific differences
#
case "$(uname -s)" in

  Linux)
    LINE_SEPARATOR='\n'
	;;
  
  Darwin)
    LINE_SEPARATOR='\n'
 	;;

  MINGW64*)
    LINE_SEPARATOR='\r\n'
	;;
esac

#
# Get the OAuth agent and default to Node.js
#
OAUTH_AGENT="$1"
if [ "$OAUTH_AGENT" == '' ]; then
  OAUTH_AGENT="NODE"
fi
if [ "$OAUTH_AGENT" != 'NODE' ] && [ "$OAUTH_AGENT" != 'NET' ] && [ "$OAUTH_AGENT" != 'KOTLIN' ] && [ "$OAUTH_AGENT" != 'FINANCIAL' ]; then
  echo 'An invalid value was supplied for the OAUTH_AGENT parameter'
  exit 1
fi

#
# Get the API gateway and OAuth proxy plugin to use, and default to Kong
#
OAUTH_PROXY="$2"
if [ "$OAUTH_PROXY" == '' ]; then
  OAUTH_PROXY="KONG"
fi
if [ "$OAUTH_PROXY" != 'KONG' ] && [ "$OAUTH_PROXY" != 'NGINX' ] && [ "$OAUTH_PROXY" != 'OPENRESTY' ]; then
  echo 'An invalid value was supplied for the OAUTH_PROXY parameter'
  exit 1
fi
echo "Deploying resources for the $OAUTH_AGENT OAuth agent and $OAUTH_PROXY API gateway and plugin ..."

#
# Set some properties differently for the more complex financial grade setup
#
if [ "$OAUTH_AGENT" == 'FINANCIAL' ]; then
  DOCKER_COMPOSE_FILE='docker-compose-financial.yml'
  SCHEME='https'
  GATEWAY_PORT=443
  SSL_CERT_FILE_PATH='./certs/example.server.p12'
  SSL_CERT_PASSWORD='Password1'
  NGINX_TEMPLATE_FILE_NAME='default.conf.financial.template'
else
  DOCKER_COMPOSE_FILE='docker-compose-standard.yml'
  SCHEME='http'
  GATEWAY_PORT=80
  SSL_CERT_FILE_PATH=''
  SSL_CERT_PASSWORD=''
  NGINX_TEMPLATE_FILE_NAME='default.conf.standard.template'
fi

#
# These variables are passed in from the parent deploy.sh script in the spa-using-token-handler repo
# When not supplied, set default values so that the spa-deployments repo can be tested in isolation
#
if [ "$BASE_DOMAIN" == "" ]; then
  BASE_DOMAIN='example.com'
  WEB_SUBDOMAIN='www'
  API_SUBDOMAIN='api'
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
# Set full domain paths
#
WEB_DOMAIN=$BASE_DOMAIN
if [ "$WEB_SUBDOMAIN" != "" ]; then
  WEB_DOMAIN="$WEB_SUBDOMAIN.$BASE_DOMAIN"
fi
API_DOMAIN=$BASE_DOMAIN
if [ "$API_SUBDOMAIN" != "" ]; then
  API_DOMAIN="$API_SUBDOMAIN.$BASE_DOMAIN"
fi
IDSVR_DOMAIN=$BASE_DOMAIN
if [ "$IDSVR_SUBDOMAIN" != "" ]; then
  IDSVR_DOMAIN="$IDSVR_SUBDOMAIN.$BASE_DOMAIN"
fi
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
  IDSVR_BASE_URL="$SCHEME://$IDSVR_DOMAIN:8443"
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
# In development mode the web host runs locally on port 80 or 443, so use a different gateway port
#
if [ "$DEVELOPMENT" == 'true' ]; then
  WEBHOST_PROFILE='WITHOUT_WEBHOST'
  GATEWAY_PORT=3000
else
  WEBHOST_PROFILE='WITH_WEBHOST'
fi

#
# Supply the 32 byte encryption key for AES256 as an environment variable
#
ENCRYPTION_KEY=$(openssl rand 32 | xxd -p -c 64)
echo -n $ENCRYPTION_KEY > encryption.key

#
# Disable CORS when web content and token handler are hosted in the same domain
#
if [ "$WEB_DOMAIN" == "$API_DOMAIN" ]; then
  CORS_ENABLED='false'
  CORS_ENABLED_NGINX='off'
else
  CORS_ENABLED='true'
  CORS_ENABLED_NGINX='on'
fi

#
# Export variables needed for substitution and deployment
#
export GATEWAY_PORT
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
export CORS_ENABLED
export CORS_ENABLED_NGINX

#
# Create certificates when deploying a financial grade setup
# Also set a variable passed through to components/idsvr/config-backup-financial.xml
#
if [ "$OAUTH_AGENT" == 'FINANCIAL' ]; then

  if [ ! -f './certs/example.ca.pem' ]; then
    ./certs/create-certs.sh
    if [ $? -ne 0 ]; then
      echo "Problem encountered creating and installing certificates"
      exit 1
    fi
  fi
  export FINANCIAL_GRADE_CLIENT_CA=$(openssl base64 -in './certs/example.ca.pem' | tr -d "$LINE_SEPARATOR")
fi

#
# Update template files with the encryption key and other supplied environment variables
#
cd components
envsubst < ./spa/config-template.json     > ./spa/config.json
envsubst < ./webhost/config-template.json > ./webhost/config.json
envsubst < ./api/config-template.json     > ./api/config.json

#
# Update the API routes with runtime values, including the cookie encryption key
#
cd api-gateway
if [ "$OAUTH_PROXY" == 'KONG' ]; then

  envsubst < ./kong/kong-template.yml > ./kong/kong.yml

elif [ "$OAUTH_PROXY" == 'NGINX' ]; then

  envsubst < "./nginx/$NGINX_TEMPLATE_FILE_NAME" | sed -e 's/§/$/g' > ./nginx/default.conf

elif [ "$OAUTH_PROXY" == 'OPENRESTY' ]; then

  envsubst < "./openresty/$NGINX_TEMPLATE_FILE_NAME" > ./openresty/default.conf
fi
cd ../..

#
# Spin up all containers, using the Docker Compose file, which applies the deployed configuration
#
docker compose --project-name spa down
docker compose --file $DOCKER_COMPOSE_FILE --profile $WEBHOST_PROFILE --profile $IDSVR_PROFILE --profile $OAUTH_PROXY --project-name spa up --detach
if [ $? -ne 0 ]; then
  echo "Problem encountered starting Docker components"
  exit 1
fi

#
# Configure Identity Server certificates when deploying the financial grade scenario
#
if [ "$OAUTH_AGENT" == 'FINANCIAL' ]; then
  ./deploy-idsvr-certs.sh
fi
