#!/bin/bash


set -uo pipefail

if [[ $# -eq 0 ]] ; then
    echo "No arguments supplied"
    echo "Usage: deploy.sh <environment>"
    echo "Example: deploy.sh dev"
    exit 1
fi
env=$1
echo "Deploying $env with "workspaces/${env}.tfvars" ..."


set -x

terraform workspace new $env
terraform workspace select $env
export GODEBUG=asyncpreemptoff=1
export TF_REGISTRY_CLIENT_TIMEOUT=20000
terraform init -reconfigure 
terraform apply -var-file="workspaces/${env}.tfvars" -auto-approve
# terraform init -force-copy

set +x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/../..; pwd )"
[[ -n "${DEBUG:-}" ]] 

TMPFILE=$(mktemp)
terraform -chdir=$SCRIPTDIR output -raw configure_kubectl > "$TMPFILE"

if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  source "$TMPFILE"


kubectl apply -f  ../k8s/bootstrap/control-plane/addons/aws
kubectl apply -f  ../k8s/bootstrap/workloads/apps-$env

fi






