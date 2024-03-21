variable "domain_name" {
  description = "Route 53 domain name"
  type        = string
  default     = "calebs.xyz"
}
variable "slack_channel" {
  description = "slack channel for argo notifications"
  type        = string
  default     = "alerts"
}
variable "preview_image_list" {
  description = "docker image for different environment"
  type        = string
  default     = "web=docker_image,api=docker_image_2"
}
variable "staging_image_list" {
  description = "docker image for different environment"
  type        = string
  default     = "web=docker_image,api=docker_image_2"
}
variable "prod_image_list" {
  description = "docker image for different environment"
  type        = string
  default     = "web=docker_image,api=docker_image_2"
}
variable "secret_creds" {
  description = "aws secret manager secrets"
  type        = string
  default     = "creds"
}
variable "db_engine" {
  description = "choose db engine"
  type        = string
  default     = "postgres"
}
variable "enable_git_ssh" {
  description = "Use git ssh to access all git repos using format git@github.com:<org>"
  type        = bool
  default     = false
}
variable "ssh_key_path" {
  description = "SSH key path for git access"
  type        = string
  default     = "~/.ssh/id_rsa"
}
variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}
variable "addons" {
  description = "Kubernetes addons"
  type        = any
  default = {
    
    enable_argocd                          = true
    enable_argo_rollouts                   = true
    enable_argocd_image_updater            = true
    enable_aws_ebs_csi_resources           = true 
    enable_external_secrets                = true
    enable_aws_load_balancer_controller    = true
    enable_karpenter                       = true
    enable_external_dns                    = true
    enable_grafana                         = true
    enable_loki_stack                      = true
    enable_cluster_proportional_autoscaler = true
    enable_kube_prometheus_stack           = true
    enable_kyverno                         = true
    enable_kubecost                        = true 
   
  }
}

variable "git_repo" {
  description = "name of Git repository"
  type        = string
  default     = "argocd-terraform"
}
variable "git_owner" {
  description = "name of repository owner"
  type        = string
  default     = "ChichiCaleb"
}
variable "git_organization" {
  description = "name of git organization"
  type        = string
  default     = "https://github.com/ChichiCaleb"
  # default     = "https://github.com/${var.git_owner}"
}
# Addons Git
variable "gitops_addons_org" {
  description = "Git repository org/user contains for addons"
  type        = string
  default     = "https://github.com/ChichiCaleb"
  # default     = var.git_organization
}

variable "gitops_addons_repo" {
  description = "Git repository contains for addons"
  type        = string
  default     = "argocd-terraform"
  # default     = var.git_repo
}
variable "gitops_addons_revision" {
  description = "Git repository revision/branch/ref for addons"
  type        = string
  default     = "main"
}
variable "gitops_addons_basepath" {
  description = "Git repository base path for addons"
  type        = string
  default     = "k8s/"
}
variable "gitops_addons_path" {
  description = "Git repository path for addons"
  type        = string
  default     = "bootstrap/control-plane/addons"
}
# Workloads Git
variable "gitops_workload_org" {
  description = "Git repository org/user contains for workload"
  type        = string
  default     = "https://github.com/ChichiCaleb"
  # default     = var.git_organization
}
variable "gitops_workload_repo" {
  description = "Git repository contains for workload"
  type        = string
  default     = "argocd-terraform"
  # default     = var.git_repo
}
variable "gitops_workload_revision" {
  description = "Git repository revision/branch/ref for workload"
  type        = string
  default     = "main"
}
variable "gitops_workload_basepath" {
  description = "Git repository base path for workload"
  type        = string
  default     = "k8s/"
}
variable "gitops_workload_path" {
  description = "Git repository path for workload"
  type        = string
  default     = "apps"
}
variable "service_monitor_name" {
  description = "Git repository path for workload"
  type        = string
  default     = "staging-web-monitor"
}

variable "service_monitor_namespace" {
  description = "Git repository path for workload"
  type        = string
  default     = "staging"
}

variable "service_monitor_label_selector" {
  description = "Git repository path for workload"
  type        = string
  default     = "staging-web-prom"
}



