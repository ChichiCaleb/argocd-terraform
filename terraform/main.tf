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
  enable_external_dns                 = var.addons.enable_external_dns
  enable_external_secrets             = var.addons.enable_external_secrets
  enable_aws_load_balancer_controller = var.addons.enable_aws_load_balancer_controller
  enable_karpenter                    = var.addons.enable_karpenter


  external_dns_route53_zone_arns = [local.route53_zone_arn] 
  tags = local.tags

  depends_on = [module.eks,module.db]
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
      
      argocd_host                 = local.argocd_host
      external_dns_domain_filters = "[${local.domain_name}]"
      staging_aws_certificate_arn      = terraform.workspace == "staging" ? aws_acm_certificate_validation.this.certificate_arn : null
      prod_aws_certificate_arn         = terraform.workspace == "prod" ? aws_acm_certificate_validation.this.certificate_arn : null
      slack_token                 = jsondecode(data.aws_secretsmanager_secret_version.creds.secret_string).SLACK_TOKEN
      workload_sm_secret          = var.secret_creds
      staging_db_instance_address  = terraform.workspace == "staging" ? module.db.db_instance_address : null
      prod_db_instance_address     = terraform.workspace == "prod" ? module.db.db_instance_address : null
      slack_channel               = var.slack_channel
      preview_image_list          =var.preview_image_list
      staging_image_list          =var.staging_image_list
      git_repo                    =var.git_repo
      git_owner                   = var.git_owner
      kube_cost_host              ="kubecost-${terraform.workspace}.${local.domain_name}"
      grafana_host                ="grafana-${terraform.workspace}.${local.domain_name}"
      prometheus_host             ="prometheus-${terraform.workspace}.${local.domain_name}"
      
     
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


  engine               = var.db_engine
  engine_version       = "14"
  family               = "postgres14" 
  major_engine_version = "14"         
  instance_class       = "db.t4g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  # NOTE: Do NOT use 'user' as the value for 'username' as it throws:
  # "Error creating DB Instance: InvalidParameterValue: MasterUsername
  # user cannot be used as it is a reserved word used by the engine"
  db_name  = jsondecode(data.aws_secretsmanager_secret_version.creds.secret_string).POSTGRES_DB
  username = jsondecode(data.aws_secretsmanager_secret_version.creds.secret_string).POSTGRES_USER
  password = jsondecode(data.aws_secretsmanager_secret_version.creds.secret_string).POSTGRES_PASSWORD
  port     = 5432

  # setting manage_master_user_password_rotation to false after it
  # has been set to true previously disables automatic rotation
  # manage_master_user_password_rotation              = true
  # master_user_password_rotate_immediately           = false
  # master_user_password_rotation_schedule_expression = "rate(15 days)"

  # multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group.security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"


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
  depends_on = [module.security_group]
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

# module "terraform_state_backend" {
#   source = "cloudposse/tfstate-backend/aws"
 
#   version       = "1.4.0"
#   namespace     = "gitops"
#   stage         = "${terraform.workspace}"
#   name          = "app-backend"
#   attributes    = ["state"]
#   terraform_backend_config_file_path = "."
#   terraform_backend_config_file_name = "backend.tf"
#   force_destroy = false
# }


