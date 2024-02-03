################################################################################
# EKS Blueprints Addons
################################################################################
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Using GitOps Bridge (Skip Helm Install in Terraform)
  create_kubernetes_resources = false

 
  # EKS Blueprints Addons
  enable_cert_manager                 = var.addons.enable_cert_manager
  enable_aws_efs_csi_driver           = var.addons.enable_aws_efs_csi_driver
  enable_aws_cloudwatch_metrics       = var.addons.enable_aws_cloudwatch_metrics
  enable_cluster_autoscaler           = var.addons.enable_cluster_autoscaler
  enable_external_dns                 = var.addons.enable_external_dns
  enable_external_secrets             = var.addons.enable_external_secrets
  enable_aws_load_balancer_controller = var.addons.enable_aws_load_balancer_controller
  enable_aws_for_fluentbit            = var.addons.enable_aws_for_fluentbit
  enable_aws_node_termination_handler = var.addons.enable_aws_node_termination_handler
  enable_aws_gateway_api_controller   = var.addons.enable_aws_gateway_api_controller
  
  external_dns_route53_zone_arns = [local.route53_zone_arn]

  tags = local.tags

  depends_on = [module.eks]
}



locals {
  enable_ingress = true
  is_route53_private_zone = false
  domain_name      = var.domain_name
  argocd_subdomain = "argocd"
  environment      =  var.environment
  argocd_host      = "${local.argocd_subdomain}.${local.domain_name}"
  route53_zone_arn = try(data.aws_route53_zone.this[0].arn, "")
 

  cluster_metadata = merge(
    module.eks_blueprints_addons.gitops_metadata,
    {
      aws_cluster_name = module.eks.cluster_name
      aws_region       = local.region
      aws_account_id   = data.aws_caller_identity.current.account_id
      aws_vpc_id       = module.vpc.vpc_id
    },

     {
       argocd_hosts                = "[${local.argocd_host}]"
       external_dns_domain_filters = "[${local.domain_name}]"
       certificate_arn             = aws_acm_certificate.cert[0].arn
    },
    {
      addons_repo_url      = "${var.gitops_addons_org}/${var.gitops_addons_repo}"
      addons_repo_basepath = var.gitops_addons_basepath
      addons_repo_path     = var.gitops_addons_path
      addons_repo_revision = var.gitops_addons_revision
    },
    {
      workload_repo_url      = "${var.gitops_workload_org}/${var.gitops_workload_repo}"
      workload_repo_basepath = var.gitops_workload_basepath
      workload_repo_path     = var.gitops_workload_path
      workload_repo_revision = var.gitops_workload_revision
    },

  )

  cluster_labels = merge(
    var.addons,
    { environment =  local.environment },
    { kubernetes_version = var.kubernetes_version },
    { aws_cluster_name = module.eks.cluster_name }
  )

  

   argocd_apps = {
    addons    = file("../k8s/bootstrap/addons.yaml")
    workloads = file("../k8s/bootstrap/workloads.yaml")
  }


}

 resource "helm_release" "updater" {
  name = "updater"
  description = "A Helm chart to install the ArgoCD image updater"
  namespace        = "argocd"
  create_namespace = false
  chart            = "argocd-image-updater"
  version          = "0.9.1"
  repository       = "https://argoproj.github.io/argo-helm"
  values = [
    <<-EOT
      metrics:
          enabled: true
    EOT
  ]

  depends_on = [module.eks_blueprints_addons,kubernetes_namespace.argocd, kubernetes_secret.git_secrets]
      
  }

################################################################################
# GitOps Bridge: Bootstrap for In-Cluster
################################################################################
module "gitops_bridge_bootstrap" {
  source = "github.com/gitops-bridge-dev/gitops-bridge-argocd-bootstrap-terraform?ref=v2.0.0"
 
  cluster = {
    metadata = local.cluster_metadata
    addons   = local.cluster_labels
    environment  = local.environment
  }
  apps       = local.argocd_apps
  argocd = {
    create_namespace = false
    set = [
      {
        name  = "server.service.type"
        value = "LoadBalancer"
      }
    ]
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argo.id
      }
    ]
  }
  depends_on = [module.eks_blueprints_addons, kubernetes_namespace.argocd, kubernetes_secret.git_secrets]
}



################################################################################
# Route 53
################################################################################
# To get the hosted zone to be use in argocd domain
data "aws_route53_zone" "this" {
  count        = local.enable_ingress ? 1 : 0
  name         = var.domain_name
  
  private_zone = local.is_route53_private_zone
}


################################################################################
# ACM Certificate
################################################################################

resource "aws_acm_certificate" "cert" {
  count             = local.enable_ingress ? 1 : 0
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  count           = local.enable_ingress ? 1 : 0
  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = tolist(aws_acm_certificate.cert[0].domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.cert[0].domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.cert[0].domain_validation_options)[0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
 
}

resource "aws_acm_certificate_validation" "this" {
  count                   = local.enable_ingress ? 1 : 0
  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}



module "terraform_state_backend" {
  source = "cloudposse/tfstate-backend/aws"
 
  version       = "1.4.0"
  namespace     = "hc"
  stage         = "staging"
  name          = "calcom-app"
  attributes    = ["state"]
  force_destroy = false
}

# place in main.tf file
# terraform init
# terraform apply -auto-approve
# terraform init -force-copy