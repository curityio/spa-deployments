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

# Uncomment when developing in this repo
# The Identity Server can be on a separate domain to the base domain
#BASE_DOMAIN='myproduct.com'
#WEB_SUBDOMAIN='www'
#API_SUBDOMAIN='api'
#IDSVR_DOMAIN='login.mycompany.com'

# Calculated values
WEB_DOMAIN=$BASE_DOMAIN
if [ "$WEB_SUBDOMAIN" != "" ]; then
  WEB_DOMAIN="$WEB_SUBDOMAIN.$BASE_DOMAIN"
fi
API_DOMAIN="$API_SUBDOMAIN.$BASE_DOMAIN"
INTERNAL_DOMAIN="internal-$BASE_DOMAIN"

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

#
# Spin up all containers, using the Docker Compose file, which applies the deployed configuration
#
docker compose --project-name spa up --force-recreate --detach --remove-orphans
if [ $? -ne 0 ]; then
  echo "Problem encountered starting Docker components"
  exit 1
fi
