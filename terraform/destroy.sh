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

TMPFILE=$(mktemp)
terraform -chdir=$SCRIPTDIR output -raw configure_kubectl > "$TMPFILE"

if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  source "$TMPFILE"

kubectl patch ns argocd \
  --type json \
  --patch='[ { "op": "remove", "path": "/spec/finalizers" } ]' 

kubectl delete ing -n $env guestbook-ui


kubectl patch -n argocd applicationset/guestbook \
  --type json \
  --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'

wait 60s

kubectl patch -n argocd applicationset/guestbook \
  --type json \
  --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
  
fi
terraform destroy -auto-approve 




