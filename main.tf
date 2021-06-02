// based on https://github.com/trussworks/terraform-aws-ecs-service/blob/f6fe5fa0c2b8e8ecf8e904b4d885dc9302a617f5/examples/load-balancer/main.tf

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix     = var.name_suffix != "" ? var.name_suffix : random_id.suffix.hex
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-main-${local.suffix}"
}

module "alb" {
  source             = "terraform-aws-modules/alb/aws"
  version            = "~> 6.0"
  name               = "${var.name_prefix}-service"
  load_balancer_type = "application"
  vpc_id             = var.vpc_id
  subnets            = var.subnet_ids
  security_groups    = [module.alb_security_group.security_group_id]
  internal           = false

  access_logs = {
    enabled = var.access_logs_enabled
    bucket = var.access_logs_bucket
    prefix = var.access_logs_prefix
  }

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = module.acm[0].this_acm_certificate_arn
      target_group_index = 0
    }
  ]

  https_listener_rules = [for i,c in var.containers: {
    https_listener_index = 0
    actions = [{
      type               = "forward"
      target_group_index = i
    }]
    conditions = [{
      host_headers = [ c.domain ]
    }]
  }]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      action_type = "redirect"
      redirect = {
        port = "443"
        protocol = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  ]

  target_groups = [for c in var.containers :
    {
      name                 = c.name
      backend_protocol     = "HTTP"
      backend_port         = c.backend_port
      target_type          = "ip"
      deregistration_delay = 90

      health_check = {
        port                = c.health_check_port
        protocol            = "HTTP"
        timeout             = 5
        interval            = 30
        path                = c.health_check_path
        healthy_threshold   = 3
        unhealthy_threshold = 3
        matcher             = "200"
      }
    }
  ]

  tags = var.tags
}

#######################################
# KMS

data "aws_iam_policy_document" "cloudwatch_logs_allow_kms" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${local.account_id}:root",
      ]
    }
    actions = [
      "kms:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Allow logs KMS access"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "main" {
  description         = "${var.name_prefix} Key for ECS log encryption"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.cloudwatch_logs_allow_kms.json
}

#######################################
# alb security group

module "alb_security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  name        = "${var.name_prefix}-service-${local.suffix}"
  description = "${var.name_prefix} security group"
  vpc_id      = var.vpc_id
  tags        = var.tags
  ingress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "service port 80"
    },
    {
      rule        = "https-443-tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "service port 443"
    },
  ]

  egress_with_cidr_blocks = flatten([
    for i, cidr_block in var.subnets_cidr_blocks : [for j, c in var.containers : {
      from_port   = c.backend_port
      to_port     = c.backend_port
      protocol    = "tcp"
      cidr_blocks = cidr_block
      description = "container port ${c.backend_port}"
    }]
  ])
}

#######################################
# domain

module "acm" {
  count                     = length(var.containers)
  source                    = "terraform-aws-modules/acm/aws"
  version                   = "~> v2.0"
  domain_name               = var.containers[count.index].domain
  zone_id                   = var.route53_zone_id
  subject_alternative_names = []
  tags                      = var.tags
}

// https://aws.amazon.com/blogs/aws/new-application-load-balancer-sni/
resource "aws_lb_listener_certificate" "additional_acm" {
  count           = length(var.containers) - 1
  listener_arn    = module.alb.https_listener_arns[0]
  certificate_arn = module.acm[count.index+1].this_acm_certificate_arn
}

resource "aws_route53_record" "service" {
  count   = length([for i,c in var.containers: c.domain])
  zone_id = var.route53_zone_id
  name    = var.containers[count.index].domain
  type    = "A"
  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}

