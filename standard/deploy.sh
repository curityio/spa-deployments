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
# The Identity Server can be on a separate domain to the web and API domain
#export WEB_DOMAIN=www.customer-internal.com
#export API_DOMAIN=api.customer-internal.com
#export IDSVR_DOMAIN=login.customer.com

#
# Supply the 32 byte encryption key for AES256 as an environment variable
#
export ENCRYPTION_KEY=$(openssl rand 32 | xxd -p -c 64)
echo -n $ENCRYPTION_KEY > encryption.key

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
