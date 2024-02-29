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

set +x

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/../..; pwd )"
[[ -n "${DEBUG:-}" ]] 

TMPFILE=$(mktemp)
terraform -chdir=$SCRIPTDIR output -raw configure_kubectl > "$TMPFILE"

if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  source "$TMPFILE"

certificate_arn=$(kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o json | jq -r '.items[0].metadata.annotations.aws_certificate_arn')
secret_identifier=$(kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o json | jq -r '.items[0].metadata.annotations.workload_sm_secret')
region=$(kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o json | jq -r '.items[0].metadata.annotations.aws_region')

echo CERTIFICATE_ARN=$certificate_arn > ../k8s/apps/guestbook/base/environment-properties.env
echo SECRET_IDENTIFIER=$secret_identifier > ../k8s/apps/guestbook/base/environment-properties.env
echo REGION=$region > ../k8s/apps/guestbook/base/environment-properties.env

kubectl apply -k  ../k8s/apps/guestbook/environments/$env

fi




