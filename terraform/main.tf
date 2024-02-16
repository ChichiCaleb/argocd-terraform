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
  enable_karpenter                    = var.addons.enable_karpenter
  enable_velero                       = var.addons.enable_velero
  

  
  external_dns_route53_zone_arns = [local.route53_zone_arn] # ArgoCD Server and UI domain name is registered in 
  tags = local.tags
  depends_on = [module.eks]
}

locals {

  
  is_route53_private_zone = false
  domain_name      = var.domain_name
  argocd_subdomain = "argocd"
  argocd_host      = "${local.argocd_subdomain}.${local.domain_name}"
  route53_zone_arn = try(data.aws_route53_zone.this.arn, "")

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
      aws_certificate_arn         = aws_acm_certificate_validation.this.certificate_arn
     
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
    }
  )

  cluster_labels = merge(
    var.addons,
    { environment = var.environment},
    { kubernetes_version = var.kubernetes_version },
    { aws_cluster_name = module.eks.cluster_name }
  )

}

################################################################################
# GitOps Bridge: Bootstrap for In-Cluster
################################################################################
module "gitops_bridge_bootstrap" {
  source = "gitops-bridge-dev/gitops-bridge/helm"

  cluster = {
    metadata = local.cluster_metadata
    addons   = local.cluster_labels
    environment  = var.environment
  }
  
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
# GitOps Bridge: Bootstrap for Apps
################################################################################
module "argocd" {
  source = "./modules/argocd-bootstrap"

  count = var.enable_gitops_auto_bootstrap ? 1 : 0

  addons = {
    repo_url        = "${var.gitops_addons_org}/${var.gitops_addons_repo}"
    path            = "${var.gitops_addons_basepath}${var.gitops_addons_path}"
    target_revision = var.gitops_addons_revision
  }
  workloads = {
    repo_url        = "${var.gitops_workload_org}/${var.gitops_workload_repo}"
    path            = "${var.gitops_workload_basepath}bootstrap/workloads"
    target_revision = var.gitops_addons_revision
  }
  depends_on = [module.gitops_bridge_bootstrap]
}


################################################################################
# Route 53
################################################################################

data "aws_route53_zone" "this" {
  name         = local.domain_name
  private_zone = local.is_route53_private_zone
}



################################################################################
# ACM Certificate
################################################################################

resource "aws_acm_certificate" "cert" {
  domain_name       = local.domain_name
  subject_alternative_names = ["*.${local.domain_name}"]
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
     }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}


# resource "aws_route53_record" "validation" {
#   count           = 2
#   zone_id         = data.aws_route53_zone.this.zone_id
#   name            = tolist(aws_acm_certificate.cert.domain_validation_options)[count.index].resource_record_name
#   type            = tolist(aws_acm_certificate.cert.domain_validation_options)[count.index].resource_record_type
#   records         = [tolist(aws_acm_certificate.cert.domain_validation_options)[count.index].resource_record_value]
#   ttl             = 60
#   allow_overwrite = true
# }






