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

  external_dns_route53_zone_arns = [local.route53_zone_arn] 
  tags = local.tags

  depends_on = [module.eks]
}

locals {
  is_route53_private_zone = false
  domain_name      = var.domain_name
  argocd_subdomain = "argocd"
  argocd_host      = "${local.argocd_subdomain}-${terraform.workspace}.${local.domain_name}"
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
      slack_token         = jsondecode(data.aws_secretsmanager_secret_version.creds.secret_string).slackToken
      workload_sm_secret          = var.secret_creds
     
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
    { environment = local.environment},
    { kubernetes_version = var.kubernetes_version },
    { aws_cluster_name = module.eks.cluster_name }
  )

}

################################################################################
# Secret Manager 
################################################################################

data "aws_secretsmanager_secret_version" "creds" {
  secret_id = var.secret_creds
}

################################################################################
# GitOps Bridge: Bootstrap for In-Cluster
################################################################################
module "gitops_bridge_bootstrap" {
   source = "gitops-bridge-dev/gitops-bridge/helm"

  cluster = {
    metadata = local.cluster_metadata
    addons   = local.cluster_labels
    environment  = local.environment
  }
  #apps       = local.argocd_apps
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

  # count = var.enable_gitops_auto_bootstrap ? 1 : 0

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


################################################################################
# RDS Module
################################################################################

module "db" {
 
  source = "terraform-aws-modules/rds/aws"

  identifier = "${local.name}-postgresql"


  engine               = "postgres"
  engine_version       = "14"
  family               = "postgres14" 
  major_engine_version = "14"         
  instance_class       = "db.t4g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = "completePostgresql"
  username = "complete_postgresql"
  port     = 5432

  # setting manage_master_user_password_rotation to false after it
  # has been set to true previously disables automatic rotation
  manage_master_user_password_rotation              = true
  master_user_password_rotate_immediately           = false
  master_user_password_rotation_schedule_expression = "rate(15 days)"

  # multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
#   enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
#   create_cloudwatch_log_group     = true

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_name                  = "monitoring-role-name"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "Description for monitoring role"

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  tags = local.tags
  db_option_group_tags = {
    "Sensitive" = "low"
  }
  db_parameter_group_tags = {
    "Sensitive" = "low"
  }
}


module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        ="${local.name}-postgres-sg"
  description = "Complete PostgreSQL  security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  tags = local.tags
}

