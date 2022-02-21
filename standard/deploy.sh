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
# Uncomment if developing in this repo and running its build script directly
#
BASE_DOMAIN='example.com'
WEB_SUBDOMAIN='www'
API_SUBDOMAIN='api'
IDSVR_SUBDOMAIN='login'
EXTERNAL_IDSVR_BASE_URL=
EXTERNAL_IDSVR_METADATA_PATH=
#export EXTERNAL_IDSVR_BASE_URL='https://idsvr.external.com'
#export EXTERNAL_IDSVR_METADATA_PATH='/oauth/v2/oauth-anonymous/.well-known/openid-configuration'

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
# Support using an external identity provider, which must be preconfigured
#
if [ "$EXTERNAL_IDSVR_BASE_URL" != "" ] && [ "$EXTERNAL_IDSVR_METADATA_PATH" != "" ]; then

  IDSVR_BASE_URL=$EXTERNAL_IDSVR_BASE_URL
  IDSVR_INTERNAL_BASE_URL=$EXTERNAL_IDSVR_BASE_URL
  DEPLOYMENT_PROFILE='WITHOUT_IDSVR'

else

  IDSVR_BASE_URL="http://$IDSVR_SUBDOMAIN.$BASE_DOMAIN:8443"
  IDSVR_INTERNAL_BASE_URL="http://login-$INTERNAL_DOMAIN:8443"
  DEPLOYMENT_PROFILE='WITH_IDSVR'
fi

# 1. Retest scenarios
# 2. Get Docker compose not running IDSVR
# 3. Produce OAuth URLs from metadata

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
export ENCRYPTION_KEY

#
# Update template files with the encryption key and other supplied environment variables
#
envsubst < ./spa/config-template.json        > ./spa/config.json
envsubst < ./webhost/config-template.json    > ./webhost/config.json
envsubst < ./api/config-template.json        > ./api/config.json
envsubst < ./reverse-proxy/kong-template.yml > ./reverse-proxy/kong.yml

#
# Spin up all containers, using the Docker Compose file, which applies the deployed configuration
#
docker compose --project-name spa up --force-recreate --detach --remove-orphans
if [ $? -ne 0 ]; then
  echo "Problem encountered starting Docker components"
  exit 1
fi
