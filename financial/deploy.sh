#!/bin/bash

#############################################################################
# A script to deploy Token Handler resources for the financial-grade scenario
#############################################################################

RESTCONF_BASE_URL='https://localhost:6749/admin/api/restconf/data'
ADMIN_USER='admin'
ADMIN_PASSWORD='Password1'
IDENTITY_SERVER_TLS_NAME='Identity_Server_TLS'
PRIVATE_KEY_PASSWORD='Password1'

#
# Ensure that we are in the folder containing this script
#
cd "$(dirname "${BASH_SOURCE[0]}")"

#
# First check prerequisites
#
if [ ! -f './idsvr/license.json' ]; then
  echo "Please provide a license.json file in the financial/idsvr folder in order to deploy the system"
  exit 1
fi

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
IDSVR_DOMAIN="$IDSVR_SUBDOMAIN.$BASE_DOMAIN"
INTERNAL_DOMAIN="internal.$BASE_DOMAIN"

#
# Support using an external identity provider, which must be preconfigured
#
if [ "$EXTERNAL_IDSVR_ISSUER_URI" != "" ]; then

  # Point to an external identity server if required
  IDSVR_BASE_URL="$(echo $EXTERNAL_IDSVR_ISSUER_URI | cut -d/ -f1-3)"
  IDSVR_INTERNAL_BASE_URL="$IDSVR_BASE_URL"
  DEPLOYMENT_PROFILE='WITHOUT_IDSVR'

  # Get the data
  HTTP_STATUS=$(curl -k -s "$EXTERNAL_IDSVR_ISSUER_URI/.well-known/openid-configuration" \
    -o metadata.json -w '%{http_code}')
  if [ "$HTTP_STATUS" != '200' ]; then
    echo "Problem encountered downloading metadata from external Identity Server: $HTTP_STATUS"
    exit 1
  fi

  # Read endpoints
  METADATA=$(cat metadata.json)
  ISSUER_URI="$EXTERNAL_IDSVR_ISSUER_URI"
  AUTHORIZE_ENDPOINT=$(jq -r .authorization_endpoint <<< "$METADATA")
  AUTHORIZE_EXTERNAL_ENDPOINT=$AUTHORIZE_ENDPOINT
  TOKEN_ENDPOINT=$(jq -r .token_endpoint <<< "$METADATA")
  USERINFO_ENDPOINT=$(jq -r .userinfo_endpoint <<< "$METADATA")
  INTROSPECTION_ENDPOINT=$(jq -r .introspection_endpoint <<< "$METADATA")
  JWKS_ENDPOINT=$(jq -r .jwks_uri <<< "$METADATA")
  LOGOUT_ENDPOINT=$(jq -r .end_session_endpoint <<< "$METADATA")

else

  # Deploy a Docker based identity server
  IDSVR_BASE_URL="https://$IDSVR_SUBDOMAIN.$BASE_DOMAIN:8443"
  IDSVR_INTERNAL_BASE_URL="https://login-$INTERNAL_DOMAIN:8443"
  DEPLOYMENT_PROFILE='WITH_IDSVR'

  # Use Docker standard endpoints
  ISSUER_URI="$IDSVR_BASE_URL/oauth/v2/oauth-anonymous"
  AUTHORIZE_ENDPOINT="$IDSVR_INTERNAL_BASE_URL/oauth/v2/oauth-authorize"
  AUTHORIZE_EXTERNAL_ENDPOINT="$IDSVR_BASE_URL/oauth/v2/oauth-authorize"
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
export IDSVR_DOMAIN
export INTERNAL_DOMAIN
export IDSVR_BASE_URL
export IDSVR_INTERNAL_BASE_URL
export ISSUER_URI
export AUTHORIZE_ENDPOINT
export AUTHORIZE_EXTERNAL_ENDPOINT
export TOKEN_ENDPOINT
export INTROSPECTION_ENDPOINT
export JWKS_ENDPOINT
export LOGOUT_ENDPOINT
export ENCRYPTION_KEY

#
# Update template files with the encryption key and other supplied environment variables
#
envsubst < ./spa/config-template.json        > ./spa/config.json
envsubst < ./webhost/config-template.json    > ./webhost/config.json
envsubst < ./api/config-template.json        > ./api/config.json
envsubst < ./reverse-proxy/kong-template.yml > ./reverse-proxy/kong.yml
envsubst < ./certs/extensions-template.cnf   > ./certs/extensions.cnf

#
# Generate OpenSSL certificates for development
#
cd certs
./create-certs.sh
if [ $? -ne 0 ]; then
  echo "Problem encountered creating and installing certificates"
  exit 1
fi
cd ..

#
# Set an environment variable to reference the root CA used for the development setup
# This is passed through to the Docker Compose file and then to the config_backup.xml file
#
export FINANCIAL_GRADE_CLIENT_CA=$(openssl base64 -in './certs/example.ca.pem' | tr -d '\n')

#
# Spin up all containers, using the Docker Compose file, which applies the deployed configuration
#
docker compose --project-name spa down
docker compose --profile $DEPLOYMENT_PROFILE --project-name spa up --detach
if [ $? -ne 0 ]; then
  echo "Problem encountered starting Docker components"
  exit 1
fi

#
# Wait for the admin endpoint to become available
#
echo "Waiting for the Curity Identity Server ..."
while [ "$(curl -k -s -o /dev/null -w ''%{http_code}'' -u "$ADMIN_USER:$ADMIN_PASSWORD" "$RESTCONF_BASE_URL?content=config")" != "200" ]; do
  sleep 2
done

#
# Add the SSL key and use the private key password to protect it in transit
#
export IDENTITY_SERVER_TLS_DATA=$(openssl base64 -in ./certs/example.server.p12 | tr -d '\n')
echo "Updating SSL certificate ..."
HTTP_STATUS=$(curl -k -s \
-X POST "$RESTCONF_BASE_URL/base:facilities/crypto/add-ssl-server-keystore" \
-u "$ADMIN_USER:$ADMIN_PASSWORD" \
-H 'Content-Type: application/yang-data+json' \
-d "{\"id\":\"$IDENTITY_SERVER_TLS_NAME\",\"password\":\"$PRIVATE_KEY_PASSWORD\",\"keystore\":\"$IDENTITY_SERVER_TLS_DATA\"}" \
-o /dev/null -w '%{http_code}')
if [ "$HTTP_STATUS" != '200' ]; then
  echo "Problem encountered updating the runtime SSL certificate: $HTTP_STATUS"
  exit 1
fi

#
# Set the SSL key as active for the runtime service role
#
HTTP_STATUS=$(curl -k -s \
-X PATCH "$RESTCONF_BASE_URL/base:environments/base:environment/base:services/base:service-role=default" \
-u "$ADMIN_USER:$ADMIN_PASSWORD" \
-H 'Content-Type: application/yang-data+json' \
-d "{\"base:service-role\": [{\"ssl-server-keystore\":\"$IDENTITY_SERVER_TLS_NAME\"}]}" \
-o /dev/null -w '%{http_code}')
if [ "$HTTP_STATUS" != '204' ]; then
  echo "Problem encountered updating the runtime SSL certificate: $HTTP_STATUS"
  exit 1
fi
