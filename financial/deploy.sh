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
# Uncomment if developing in this repo and running its build script directly
#
export BASE_DOMAIN='example.com'
export WEB_SUBDOMAIN='www'
export API_SUBDOMAIN='api'
export IDSVR_SUBDOMAIN='login'
export EXTERNAL_IDSVR_DOMAIN=
export EXTERNAL_IDSVR_METADATA_PATH=

# Calculated values
WEB_DOMAIN=$BASE_DOMAIN
if [ "$WEB_SUBDOMAIN" != "" ]; then
  WEB_DOMAIN="$WEB_SUBDOMAIN.$BASE_DOMAIN"
fi
API_DOMAIN="$API_SUBDOMAIN.$BASE_DOMAIN"
IDSVR_DOMAIN="$IDSVR_SUBDOMAIN.$BASE_DOMAIN"
INTERNAL_DOMAIN="internal.$BASE_DOMAIN"

#
# Supply the 32 byte encryption key for AES256 as an environment variable
#
ENCRYPTION_KEY=$(openssl rand 32 | xxd -p -c 64)
echo -n $ENCRYPTION_KEY > encryption.key

#
# Export variables needed for substitution
#
export BASE_DOMAIN
export WEB_DOMAIN
export API_DOMAIN
export IDSVR_DOMAIN
export INTERNAL_DOMAIN
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
  echo "Problem encountered creating and installing certificates for the Token Handler"
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
docker compose --project-name spa up --detach --force-recreate --remove-orphans
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
