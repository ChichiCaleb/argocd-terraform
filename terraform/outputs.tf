output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = <<-EOT
    export KUBECONFIG="/tmp/${module.eks.cluster_name}"
    aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}
  EOT
}

output "configure_argocd" {
  description = "Terminal Setup"
  value       = <<-EOT
    export KUBECONFIG="/tmp/${module.eks.cluster_name}"
    aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}
    export ARGOCD_OPTS="--port-forward --port-forward-namespace argocd --grpc-web"
    kubectl config set-context --current --namespace argocd
    argocd login --port-forward --username admin --password $(aws secretsmanager get-secret-value --secret-id argocd-${terraform.workspace} --region ${local.region} --output json | jq -r .SecretString)

    echo "ArgoCD Username: admin"
    echo "ArgoCD Password: $(aws secretsmanager get-secret-value --secret-id argocd-${terraform.workspace} --region ${local.region} --output json | jq -r .SecretString)"
    echo Port Forward: http://localhost:8080
    kubectl port-forward -n argocd svc/argo-cd-argocd-server 8080:80
    EOT
}
#echo "ArgoCD Password: $(kubectl get secrets argocd-initial-admin-secret -n argocd --template="{{index .data.password | base64decode}}")"
output "access_argocd" {
  description = "ArgoCD Access"
  value       = <<-EOT
    export KUBECONFIG="/tmp/${module.eks.cluster_name}"
    aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}
    echo "ArgoCD Username: admin"
    echo "ArgoCD Password: $(aws secretsmanager get-secret-value --secret-id argocd-${terraform.workspace} --region ${local.region} --output json | jq -r .SecretString)"
    echo "ArgoCD URL: https://$(kubectl get ing -n argocd argo-cd-argocd-server -o jsonpath='{.spec.tls[0].hosts[0]}')"
       
        if [ "${terraform.workspace}" = "staging" ]; then
    # Loop through all Ingress resources in the specified namespace
    for ing_name in $(kubectl get ing -n "staging" | awk '/^staging-/{print $1}'); do
      
        echo "$ing_name URL: https://$(kubectl get ing -n staging "$ing_name"  -o jsonpath='{.spec.rules[0].host}')"
    done

    for namespace in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
        # Check if the namespace starts with "preview"
        if [[ "$namespace" == preview* ]]; then
            # Loop through all Ingress resources in the current namespace
            for ing_name in $(kubectl get ing -n "$namespace" | awk '/^preview-/{print $1}'); do
              echo "$namespace URL: https://$(kubectl get ing -n "$namespace" "$ing_name"  -o jsonpath='{.spec.rules[0].host}')"
            done
        fi
    done

    elif [ "${terraform.workspace}" = "prod" ]; then
    # Loop through all Ingress resources in the specified namespace
    for ing_name in $(kubectl get ing -n "prod" | awk '/^prod-/{print $1}'); do
      
        echo "$ing_name URL: https://$(kubectl get ing -n prod "$ing_name"  -o jsonpath='{.spec.rules[0].host}')"
    done

    else
        echo "Unknown cluster: $cluster"
        exit 1
    fi
        
    
    EOT
}



