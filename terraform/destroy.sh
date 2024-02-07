#!/bin/bash

set -uo pipefail

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOTDIR="$(cd ${SCRIPTDIR}/../..; pwd )"
[[ -n "${DEBUG:-}" ]] && set -x

if [[ $# -eq 0 ]] ; then
    echo "No arguments supplied"
    echo "Usage: destroy.sh <environment>"
    echo "Example: destroy.sh dev"
    exit 1
fi

env=$1
echo "Destroying $env ..."
terraform workspace select $env

# # Delete the Ingress/SVC before removing the addons and
# delete argocd finalizer inorder to successfully run terraform destroy"
TMPFILE=$(mktemp)
terraform -chdir=$SCRIPTDIR output -raw configure_kubectl > "$TMPFILE"

# check if TMPFILE contains the string "No outputs found"
if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
 source "$TMPFILE"

 
kubectl patch -n argocd applicationset/preview-apps \
   --type json \
   --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'

kubectl patch -n argocd applicationset/workloads-staging \
  --type json \
  --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'

  
kubectl patch -n argocd applicationset/workloads-prod \
  --type json \
  --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'

  kubectl delete -n argocd applicationset cluster-addons
  kubectl delete -n argocd applicationset addons-aws-ingress-nginx
  kubectl delete svc -n ingress-nginx ingress-nginx-controller
  kubectl delete -n argocd applicationset addons-argocd
  kubectl delete -n argocd svc argo-cd-argocd-server
  kubectl delete ing -n argocd argo-cd-argocd-server
  
fi

terraform destroy -auto-approve -var-file="workspaces/${env}.tfvars" -target="module.argocd" -auto-approve
terraform destroy -auto-approve -var-file="workspaces/${env}.tfvars" -target="module.gitops_bridge_bootstrap" -auto-approve
terraform destroy -auto-approve -var-file="workspaces/${env}.tfvars" -target="module.eks_blueprints_addons" -auto-approve
terraform destroy -auto-approve -var-file="workspaces/${env}.tfvars" -target="module.eks" -auto-approve
terraform destroy -auto-approve -var-file="workspaces/${env}.tfvars" -target="module.vpc" -auto-approve
terraform destroy -auto-approve



