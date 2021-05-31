#!/bin/bash
set -e

# Source the helper functions
. functions.sh

# Set status to maintenance
lucky set-status -n config-status maintenance \
  "Updating Hasura configuration"

# Exit and block if the relation with the DB is not setup
if [ $(lucky relation list-ids -n db | wc -l) -ne 1 ]; then
  # Set config status back to active
  lucky set-status -n config-status active
  # Set relation status to blocked and exit
  lucky set-status -n pgsql-relation-status blocked \
    "One and only one relation to PostgreSQL required"
  exit 0
else
  lucky set-status -n pgsql-relation-status active
fi

# Load bash variables with configuration settings
hstag=$(lucky get-config HASURA_DOCKER_TAG)
if [ -z $hstag ]; then lucky set-status -n config-status blocked \
  "Config required: 'HASURA_DOCKER_TAG'"; exit 0; 
fi
hssecret=$(lucky get-config HASURA_ADMIN_SECRET)
hsconsole=$(lucky get-config HASURA_ENABLE_CONSOLE)


# Gather relation data
dbuser="$(lucky kv get pgsql_POSTGRES_USER)"
dbpass="$(lucky kv get pgsql_POSTGRES_PASSWORD)"
dbhost="$(lucky kv get pgsql_hostname)"
dbport="$(lucky kv get pgsql_port)"
dbname="$(lucky kv get pgsql_POSTGRES_DB)"

# Build db URL using relation data
dburl="postgres://$dbuser:$dbpass@$dbhost:$dbport/$dbname"

# Set the container image
lucky container image set "hasura/graphql-engine:${hstag}"

# Load container env vars with config settings
lucky container env set \
  "HASURA_GRAPHQL_DATABASE_URL=${dburl}" \
  "HASURA_GRAPHQL_ENABLE_CONSOLE=false" \
  "HASURA_GRAPHQL_DEV_MODE=false"

# Set optional variables
if [ -n ${hssecret} ]; then
  lucky container env set "HASURA_GRAPHQL_ADMIN_SECRET=${hssecret}"
fi
if [ "${hsconsole}" == "true" ]; then
  lucky container env set "HASURA_GRAPHQL_ENABLE_CONSOLE=true"
else
  lucky container env set "HASURA_GRAPHQL_ENABLE_CONSOLE=false"
fi

# Set up the ports
set_container_port
bind_port=$(lucky kv get bind_port)

# Remove previously opened ports
lucky port close --all
lucky container port remove --all

# Bind the app port
lucky container port add "${bind_port}:8080"
# Open the port on the firewall
lucky port open ${bind_port}

lucky set-status -n config-status active
