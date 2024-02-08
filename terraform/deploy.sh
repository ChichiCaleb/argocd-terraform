#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "No arguments supplied"
    echo "Usage: deploy.sh <environment>"
    echo "Example: deploy.sh dev"
    exit 1
fi
env=$1
echo "Deploying $env with "workspaces/${env}.tfvars" ..."

set -x

TF_REGISTRY_CLIENT_TIMEOUT=1200
TF_REGISTRY_DISCOVERY_RETRY=20

terraform workspace new $env
terraform workspace select $env
terraform init -reconfigure
terraform apply -auto-approve -var-file="workspaces/${env}.tfvars" -auto-approve