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
cluster=$1

echo "Destroying $cluster ..."
terraform workspace select $cluster

TMPFILE=$(mktemp)
terraform -chdir=$SCRIPTDIR output -raw configure_kubectl > "$TMPFILE"

if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  source "$TMPFILE"

kubectl patch ns argocd \
  --type json \
  --patch='[ { "op": "remove", "path": "/spec/finalizers" } ]' 

 if [ "$cluster" = "staging" ]; then
 kubectl patch -n argocd applicationset/apps-staging \
  --type json \
  --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' 

  kubectl patch -n argocd applicationset/apps-preview \
  --type json \
  --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' 

kubectl delete -n argocd applicationset/apps-staging 
kubectl delete -n argocd applicationset/apps-preview 

# Loop through all Ingress resources in the specified namespace
for ing_name in $(kubectl get ing -n "staging" | awk '/^staging-/{print $1}'); do
    # Delete each Ingress resource
    kubectl delete ing "$ing_name" -n "staging"
done

for namespace in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
    # Check if the namespace starts with "preview"
    if [[ "$namespace" == preview* ]]; then
        # Loop through all Ingress resources in the current namespace
        for ing_name in $(kubectl get ing -n "$namespace" | awk '/^preview-/{print $1}'); do
            # Delete each Ingress resource
            kubectl delete ing "$ing_name" -n "$namespace"
        done
    fi
done

   
elif [ "$cluster" = "prod" ]; then
 kubectl patch -n argocd applicationset/apps-prod \
  --type json \
  --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' 

kubectl delete -n argocd applicationset/apps-prod 

# Loop through all Ingress resources in the specified namespace
for ing_name in $(kubectl get ing -n "prod" | awk '/^prod-/{print $1}'); do
    # Delete each Ingress resource
    kubectl delete ing "$ing_name" -n "prod"
done
    
else
    echo "Unknown cluster: $cluster"
      exit 1
fi

fi
terraform destroy -auto-approve 


