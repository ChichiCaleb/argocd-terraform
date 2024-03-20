#!/bin/bash

# YAML file
yaml_file="values.yaml"


# Check if the YAML file exists
if [ ! -f "$yaml_file" ]; then
    echo "YAML file not found: $yaml_file"
    exit 1
fi

# Function to check if variables have changed
variables_changed() {
    local current_value=$1
    local previous_value=$2
    # echo "Comparing current value: '$current_value' with previous value: '$previous_value'"
    if [[ "$current_value" != "$previous_value" ]]; then
        return 0   # Return true if values are different
    else
        return 1   # Return false if values are the same
    fi
}
# export yaml values to be read throughout the script
export_variables() {
 # Read variables from YAML file
    while IFS=':' read -r key value; do
        if [[ ! $key =~ ^# && -n $key ]]; then
            # Sanitize the key to remove special characters
            sanitized_key=$(echo "$key" | sed 's/[^A-Za-z0-9_]/_/g')

            # Sanitize the value to remove leading/trailing spaces
            sanitized_value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

            export "$sanitized_key=$sanitized_value"
        fi
    done < "$yaml_file"   
}


# Function to assign a unique ingress group order to ingress resource created for any given service
# helps with cost optimization by using on aws application loadbalancer for multiple ingresses across diffrent namespaces
update_ingress_group_order() {
    local combination=$1
    local default_order=9999
    local ingress_group_order="generated-values/ingress_group_order.txt"

   export INGRESS_GROUP_ORDER=$default_order

    # Retrieve the last INGRESS_GROUP_ORDER from the file
   local last_order=$(tail -n1 $ingress_group_order | cut -d'=' -f2)
   
     # Check if last_order is empty
    if [ -z "$last_order" ]; then
        last_order=9999
    fi
    
# Check if the combination exists in the file
    if grep -q "^$combination=" $ingress_group_order; then
        echo "Combination already exists."
        INGRESS_GROUP_ORDER=$last_order
    else
       INGRESS_GROUP_ORDER=$((last_order - 10))
        # If the combination does not exist, append it with the initial value
        echo "$combination=$INGRESS_GROUP_ORDER" >> $ingress_group_order
        echo "Combination '$combination' assigned with $INGRESS_GROUP_ORDER."

        # Update the value in the file
        sed -i "s/^$combination=.*$/$combination=$INGRESS_GROUP_ORDER/" $ingress_group_order
    fi
 
    echo "INGRESS_GROUP_ORDER: $INGRESS_GROUP_ORDER"
}

# function to check for change in any value that requires reapplying terraform and runs the terraform 
# deploy script when necessary

check_if_any_terraform_value_changed() {
    # Flag to track changes
 change_detected=false


    # Load previous values from a file (if exists)
    if [[ -f "$values_file" ]]; then
        source "$values_file"
    fi

     env_image=TF_VAR_${environment}_image_list

    # Check if variables have changed
    if variables_changed "$base_domain" "$TF_VAR_domain_name"; then
        export TF_VAR_domain_name="$base_domain"
        echo "Change detected in $environment base_domain."
        change_detected=true
    fi

   
   if variables_changed "$secret_creds" "$TF_VAR_secret_creds"; then
        export TF_VAR_secret_creds="$secret_creds"
        echo "Change detected in  $environment secret_creds."
        change_detected=true
    fi

    if variables_changed "$enable_git_ssh" "$TF_VAR_enable_git_ssh"; then
        export TF_VAR_enable_git_ssh="$enable_git_ssh"
        echo "Change detected in $environment enable_git_ssh."
        change_detected=true
    fi

    if variables_changed "$slack_channel" "$TF_VAR_slack_channel"; then
        export TF_VAR_slack_channel="$slack_channel"
        echo "Change detected in $environment slack_channel."
        change_detected=true
    fi

    if variables_changed "$region" "$TF_VAR_region"; then
        export TF_VAR_region="$region"
        echo "Change detected in $environment region."
        change_detected=true
    fi

    if variables_changed "$git_repo" "$TF_VAR_git_repo"; then
        export TF_VAR_git_repo="$git_repo"
        echo "Change detected in $environment git_repo."
        change_detected=true
    fi
  
    if variables_changed "$db_engine" "$TF_VAR_db_engine"; then
        export TF_VAR_db_engine="$db_engine"
        echo "Change detected in $environment db_engine."
        change_detected=true
    fi

    if variables_changed "$git_owner" "$TF_VAR_git_owner"; then
    export TF_VAR_git_owner="$git_owner"
    echo "Change detected in $environment git_owner."
    change_detected=true
    fi

    # if variables_changed "$image" "${!env_image}"; then
    # export $env_image="$image"
    # echo "Change detected in either environment or $environment image."
    # change_detected=true
    # fi

    if variables_changed "$image_list" "${!env_image}"; then
    export $env_image="$image_list"
    echo "Change detected in either environment or $environment image."
    change_detected=true
    fi
    
  # Save current values for future comparison
    echo "TF_VAR_domain_name=\"$base_domain\"" > $values_file
    echo "TF_VAR_secret_creds=\"$secret_creds\"" >> $values_file
    echo "TF_VAR_enable_git_ssh=\"$enable_git_ssh\"" >> $values_file
    echo "TF_VAR_slack_channel=\"$slack_channel\"" >> $values_file
    echo "TF_VAR_region=\"$region\"" >> $values_file
    echo "TF_VAR_git_repo=\"$git_repo\"" >> $values_file
    echo "TF_VAR_db_engine=\"$db_engine\"" >> $values_file
    echo "TF_VAR_git_owner=\"$git_owner\"" >> $values_file
    echo $env_image="$image_list" >> $values_file

   

if [[ "$enable_git_ssh" = "false" ]]; then
    export TF_VAR_git_organization="https://github.com/$git_owner"
    echo "TF_VAR_git_organization=\"https://github.com/$git_owner\"" >> $values_file
elif [[ "$enable_git_ssh" = "true" ]]; then
    export TF_VAR_git_organization="git@github.com:$git_owner"
    echo "TF_VAR_git_organization=\"git@github.com:$git_owner\"" >> $values_file
else
    echo "unsupported enable_git_ssh: $enable_git_ssh"
    exit 1
fi


     # Extract the addons section from the YAML file
    addons_section=$(yq e '.addons' "$yaml_file")

    # Construct the addons object
    addons_object=""

    while IFS=':' read -r addon_key addon_value; do
        addon_key=$(echo "$addon_key" | sed 's/^[[:space:]]*//')
        addon_value=$(echo "$addon_value" | sed 's/^[[:space:]]*//')

        # Add the key-value pair to the addons object
        addons_object="$addons_object $addon_key=$addon_value"
    done < <(echo "$addons_section")

    
    # Compare current addons object with the previous one
    if [[ -f "$values_file" ]]; then
        source "$values_file"

      # Check for changes in each addon
        for addon_key_value in $addons; do
            addon_key=$(echo "$addon_key_value" | cut -d'=' -f1)
            addon_value=$(echo "$addon_key_value" | cut -d'=' -f2)

            current_value=$(echo "$addons_object" | grep -o "\b$addon_key=[^ ]*" | cut -d'=' -f2)

           if variables_changed "$current_value" "$addon_value"; then
                echo "Change detected in $environment $addon_key."
                export TF_VAR_addons="{$addons_object}"
                change_detected=true
                break   # Exit the loop if any addon change detected
            fi
        done

       
    fi

    # Save the current addons object to values.txt
    echo "addons=\"$addons_object\"" >> $values_file
# save other non-terraform values specified in the yaml file for reference purpose
    echo "------------------------------------ "  >> $values_file
    echo "------------------------------------- "  >> $values_file  
    echo "ENVIRONMENT=\"$environment\"" >> $values_file
    echo "SERVICE=\"$service\"" >> $values_file
    echo "SUB_DOMAIN=\"$sub_domain\"" >> $values_file
    echo "REPLICAS=\"$replicas\"" >> $values_file
    echo "PORT=\"$port\"" >> $values_file
 
    

    # Perform action if any change detected
        if [ "$change_detected" = true ]; then
            echo "Change detected in $environment terraform dependent values"
            echo "applying terraform modules..."
            # Perform action here
            if [ "$environment" = "staging" ] || [ "$environment" = "preview" ]; then
              cd terraform 
             ./deploy.sh staging
            elif [ "$environment" = "prod" ]; then
              cd terraform 
             ./deploy.sh prod
              
            else
               echo "Unknown environment: $ENVIRONMENT"
                 exit 1
             fi
        else
            echo "No change detected in terraform dependent values"
            echo "patching environment specific manifest..."
        fi

}


# export config values needed by kustomize configmap generator to environment-properties.env file
export_config_variable_to_kustomize() {
    # Extract the config section from the YAML file
    config_section=$(yq e '.config' "$yaml_file")

    # Temporary file to hold the updated environment properties
    temp_file=$(mktemp)

    while IFS=':' read -r config_key config_value; do
        config_key=$(echo "$config_key" | sed 's/^[[:space:]]*//')
        config_value=$(echo "$config_value" | sed 's/^[[:space:]]*//')

        echo "$config_key=$config_value" >> "$temp_file"

    done < <(echo "$config_section")

    # Move the temporary file to overwrite the environment-properties.env file
    mv "$temp_file" ./k8s/apps/base/environment-properties.env
}

# run functions

export_variables

values_file="generated-values/values-$environment.txt"

export_config_variable_to_kustomize

update_ingress_group_order "$environment-$service"

check_if_any_terraform_value_changed

# reassign variables to be used by kustomize environment patching

BASE_DOMAIN=$base_domain
ENVIRONMENT=$environment
SUB_DOMAIN=$sub_domain
SERVICE=$service
SERVICE_SELECTOR=$environment-$service
IMAGE=$image
REPLICAS=$replicas
PORT=$port
SLACK_CHANNEL=$slack_channel
SECRET_CREDS=$secret_creds
REGION=$region

# Check if $ENVIRONMENT is staging or preview
if [ "$ENVIRONMENT" = "staging" ] || [ "$ENVIRONMENT" = "preview" ]; then
 # Generate the patch file dynamically for staging and preview environment
  cat <<EOF >k8s/apps/environments/$ENVIRONMENT/patches/$SERVICE.yaml
    
    - target:
        kind: Deployment
        name: apps-deployment
      patch: |-
        - op: replace
          path: /metadata/name
          value: $SERVICE_SELECTOR

        - op: replace
          path: /metadata/labels/apps
          value: $SERVICE_SELECTOR

        - op: replace
          path: /spec/selector/matchLabels/apps
          value: $SERVICE_SELECTOR

        - op: replace
          path: /spec/template/metadata/labels/apps
          value: $SERVICE_SELECTOR
        
        - op: replace
          path: /spec/template/spec/containers/0/image
          value: $IMAGE

        - op: replace
          path: /spec/replicas
          value: $REPLICAS

        - op: replace
          path: /spec/template/spec/containers/0/ports/0/containerPort
          value: $PORT

        - op: replace
          path: /spec/template/spec/containers/0/livenessProbe/httpGet/port
          value: $PORT

        - op: replace
          path: /spec/template/spec/containers/0/readinessProbe/httpGet/port
          value: $PORT

    - target:
        kind: Service
        name: apps-service
      patch: |-
        - op: replace
          path: /metadata/name
          value: $SERVICE_SELECTOR

        - op: replace
          path: /spec/selector/apps
          value: $SERVICE_SELECTOR

        - op: replace
          path: /spec/ports/0/port
          value: $PORT

        - op: replace
          path: /spec/ports/0/targetPort
          value: $PORT

    - target:
        kind: Service
        name: apps-prom
      patch: |-
        - op: replace
          path: /metadata/name
          value: $SERVICE_SELECTOR

        - op: replace
          path: /spec/selector/apps
          value: $SERVICE_SELECTOR

    - target:
        kind: Ingress
        name: apps-ingress
      patch: |-
        - op: replace
          path: /metadata/name
          value: $SERVICE_SELECTOR

        - op: replace
          path: /spec/tls/0/hosts/0
          value: $SUB_DOMAIN

        - op: replace
          path: /spec/rules/0/host
          value: $SUB_DOMAIN

        - op: replace
          path: /spec/rules/0/http/paths/0/backend/service/name
          value: $SERVICE_SELECTOR

        
        - op: replace
          path: /metadata/annotations/[alb.ingress.kubernetes.io/group.order]
          value: $INGRESS_GROUP_ORDER

        - op: add
          path: /spec/rules/0/http/paths/0/backend/service/port
          value: number=$PORT

    - target:
        kind: ExternalSecret
        name: external-secrets-sm
      patch: |-
        - op: replace
          path: /spec/dataFrom/0/extract/key
          value: $SECRET_CREDS

    - target:
        kind: ClusterSecretStore
        name: cluster-secretstore-sm
      patch: |-
        - op: replace
          path: /spec/provider/aws/region
          value: $REGION
EOF

# Check if $ENVIRONMENT is prod
elif [ "$ENVIRONMENT" = "prod" ]; then
   # Generate the patch file dynamically for prod environment
cat <<EOF >k8s/apps/environments/$ENVIRONMENT/patches/$SERVICE.yaml

- target:
    kind: Service
    name: apps-prom
  patch: |-
    - op: replace
      path: /metadata/name
      value: $SERVICE_SELECTOR

    - op: replace
      path: /spec/selector/apps
      value: $SERVICE_SELECTOR

- target:
    kind: Ingress
    name: apps-ingress
  patch: |-
    - op: replace
      path: /metadata/name
      value: $SERVICE_SELECTOR

    - op: replace
      path: /spec/tls/0/hosts/0
      value: $BASE_DOMAIN

    - op: replace
      path: /spec/rules/0/host
      value: $BASE_DOMAIN

    - op: replace
      path: /metadata/annotations/[alb.ingress.kubernetes.io/group.order]
      value: $INGRESS_GROUP_ORDER

    - op: replace
      path: /spec/rules/0/http/paths/0/path
      value: /*

    - op: replace
      path: /spec/rules/0/http/paths/0/pathType
      value: ImplementationSpecific
    
    - op: replace
      path: /spec/rules/0/http/paths/0/backend/service/name
      value: alb-rollout-root

    - op: add
      path: /spec/rules/0/http/paths/0/backend/service/port
      value: name=use-annotation

- target:
    kind: Rollout
    name: alb-rollout
  patch: |-
    - op: replace
      path: /metadata/name
      value: $SERVICE_SELECTOR

    - op: replace
      path: /metadata/annotations/[notifications.argoproj.io/subscribe.on-rollout-step-completed.slack]
      value: $SLACK_CHANNEL

    - op: replace
      path: /metadata/annotations/[notifications.argoproj.io/subscribe.on-rollout-completed]
      value: $SLACK_CHANNEL

    - op: replace
      path: /metadata/annotations/[notifications.argoproj.io/subscribe.on-rollout-updated]
      value: $SLACK_CHANNEL

    - op: replace
      path: /metadata/annotations/[notifications.argoproj.io/subscribe.on-scaling-replica-set]
      value: $SLACK_CHANNEL

    - op: replace
      path: /spec/selector/matchLabels/apps
      value: $SERVICE_SELECTOR

    - op: replace
      path: /spec/template/metadata/labels/apps
      value: $SERVICE_SELECTOR
    
    - op: replace
      path: /spec/template/spec/containers/0/image
      value: $IMAGE

    - op: replace
      path: /spec/replicas
      value: $REPLICAS

    - op: replace
      path: /spec/template/spec/containers/0/ports/0/containerPort
      value: $PORT

    - op: replace
      path: /spec/template/spec/containers/0/livenessProbe/httpGet/port
      value: $PORT

    - op: replace
      path: /spec/strategy/canary/canaryService
      value: $SERVICE_SELECTOR-canary

    - op: replace
      path: /spec/strategy/canary/stableService
      value: $SERVICE_SELECTOR-stable

    - op: replace
      path: /spec/strategy/canary/args/0/value
      value: $SERVICE_SELECTOR

    - op: replace
      path: /spec/strategy/canary/trafficRouting/alb/ingress
      value: $SERVICE_SELECTOR

    - op: replace
      path: /spec/strategy/canary/trafficRouting/alb/rootService
      value: $SERVICE_SELECTOR-root

    - op: replace
      path: /spec/strategy/canary/trafficRouting/alb/servicePort
      value: $PORT

    - op: replace
      path: /spec/template/spec/containers/0/readinessProbe/httpGet/port
      value: $PORT

    - op: replace
      path: /spec/template/spec/containers/0/readinessProbe/httpGet/port
      value: $PORT

- target:
    kind: Service
    name: alb-rollout-root
  patch: |-
    - op: replace
      path: /metadata/name
      value: $SERVICE_SELECTOR-root

    - op: replace
      path: /spec/ports/0/port
      value: $PORT

    - op: replace
      path: /spec/selector/apps
      value: $SERVICE_SELECTOR

- target:
    kind: Service
    name: alb-rollout-canary
  patch: |-
    - op: replace
      path: /metadata/name
      value: $SERVICE_SELECTOR-canary

    - op: replace
      path: /spec/ports/0/port
      value: $PORT

    - op: replace
      path: /spec/selector/apps
      value: $SERVICE_SELECTOR

- target:
    kind: Service
    name: alb-rollout-stable
  patch: |-
    - op: replace
      path: /metadata/name
      value: $SERVICE_SELECTOR-stable

    - op: replace
      path: /spec/ports/0/port
      value: $PORT

    - op: replace
      path: /spec/selector/apps
      value: $SERVICE_SELECTOR


- target:
    kind: ExternalSecret
    name: external-secrets-sm
  patch: |-
    - op: replace
      path: /spec/dataFrom/0/extract/key
      value: $SECRET_CREDS

- target:
    kind: ClusterSecretStore
    name: cluster-secretstore-sm
  patch: |-
    - op: replace
      path: /spec/provider/aws/region
      value: $REGION

EOF

# Handle unknown environments
else
    echo "Unknown environment: $ENVIRONMENT"
    exit 1
fi



