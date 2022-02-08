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
# Supply the 32 byte encryption key for AES256 as an environment variable
#
export ENCRYPTION_KEY=$(openssl rand 32 | xxd -p -c 64)
echo -n $ENCRYPTION_KEY > encryption.key

#
# Update the template file with the encryption key
#
envsubst < reverse-proxy/kong.template.yml > ./kong/kong.yml

#
# Spin up all containers, using the Docker Compose file, which applies the deployed configuration
#
docker compose --project-name spa up --force-recreate --detach --remove-orphans
if [ $? -ne 0 ]; then
  echo "Problem encountered starting Docker components"
  exit 1
fi
