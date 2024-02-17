#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "No arguments supplied"
    echo "Usage: deploy.sh <environment>"
    echo "Example: deploy.sh dev"
    exit 1
fi
env=$1
echo "Deploying $env with "workspaces/${env}.tfvars" ..."

set -uo pipefail
set -x

terraform workspace new $env
terraform workspace select $env
terraform init -reconfigure
export GODEBUG=asyncpreemptoff=1
export TF_REGISTRY_CLIENT_TIMEOUT=20000
terraform apply -var-file="workspaces/${env}.tfvars" -auto-approve

set +x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/../..; pwd )"
[[ -n "${DEBUG:-}" ]] 

TMPFILE=$(mktemp)
terraform -chdir=$SCRIPTDIR output -raw configure_kubectl > "$TMPFILE"

if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  source "$TMPFILE"

certificate_arn=$(kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o json | jq -r '.items[0].metadata.annotations.aws_certificate_arn')

echo CERTIFICATE_ARN=$certificate_arn > ../k8s/apps/guestbook/base/environment-properties.env

kubectl apply -k  ../k8s/apps/guestbook/environments/$env 

fi



