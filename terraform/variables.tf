variable "domain_name" {
  description = "Route 53 domain name"
  type        = string
  default     = "calebs.xyz"
}
variable "secret_creds" {
  description = "aws secret manager secrets"
  type        = string
  default     = "creds"
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
    # aws
     # Enable if want argo manage argo from gitops
    enable_argocd                       = true
    enable_argocd_image_updater         = true
    enable_cert_manager                 = false
    enable_aws_ebs_csi_resources        = true # generate gp2 and gp3 storage classes for ebs-csi
    enable_aws_cloudwatch_metrics       = false
    enable_external_secrets             = true
    enable_aws_load_balancer_controller = true
    enable_aws_for_fluentbit            = false
    enable_karpenter                    = false
    enable_aws_ingress_nginx            = false # inginx configured with AWS NLB
    enable_aws_efs_csi_driver                    = false
    enable_cluster_autoscaler                    = false
    enable_external_dns                          = true
    enable_velero                                = false
    enable_sealed_secrets                        = false
    
   
    # oss
    enable_grafana                         = false
    enable_grafana_loki                    = false
    enable_argo_rollouts                   = true
    enable_cluster_proportional_autoscaler = false
    enable_kube_prometheus_stack           = true
    enable_metrics_server                  = true
    enable_kyverno                         = true
    enable_prometheus_adapter              = false
    enable_vpa                             = false
  }
}
# Addons Git
variable "gitops_addons_org" {
  description = "Git repository org/user contains for addons"
  type        = string
  default     = "https://github.com/ChichiCaleb"
}
variable "gitops_addons_repo" {
  description = "Git repository contains for addons"
  type        = string
  default     = "argocd-terraform"
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
}
variable "gitops_workload_repo" {
  description = "Git repository contains for workload"
  type        = string
  default     = "argocd-terraform"
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


