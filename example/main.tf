data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

data "aws_route53_zone" "selected" {
  name         = "example.com."
  private_zone = false
}

locals {
  name_prefix           = "fargate-service"
  region                = data.aws_region.current.name
  account_id            = data.aws_caller_identity.current.account_id
  suffix                = random_id.suffix.hex
  route53_zone_id       = data.aws_route53_zone.selected.zone_id
  target_container_port = 8080
  tags = {
    "Hello" : "World",
  }
}

module "vpc" {
  source          = "terraform-aws-modules/vpc/aws"
  version         = "~> 2.64.0"
  name            = "${local.name_prefix}-vpc"
  cidr            = "10.0.0.0/16"
  azs             = ["ap-northeast-2a", "ap-northeast-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.104.0/24", "10.0.105.0/24"]
}

module "s3_bucket_for_logs" {
  source = "terraform-aws-modules/s3-bucket/aws"
  bucket = "${local.name_prefix}-alb-logs-${local.suffix}"
  acl    = "log-delivery-write"

  # Allow deletion of non-empty bucket
  force_destroy = true
  attach_elb_log_delivery_policy = true
}

#######################################
# alb, ecs cluster

locals {
  containers = [
    {
      name = "${local.name_prefix}-tomcat"
      log_group_name = "/ecs/tomcat"
      image = "500000000002.dkr.ecr.ap-northeast-2.amazonaws.com/fargate-service-main-58f11a:v2"
      backend_port = 8080
      health_check_port = 8080
      health_check_path = "/"
      domain = "tomcat.example.com"
    },
    {
      name = "${local.name_prefix}-nginx"
      log_group_name = "/ecs/nginx"
      image = "nginx:1.19.9-alpine"
      backend_port = 80
      health_check_port = 80
      health_check_path = "/"
      domain = "nginx.example.com"
    }
  ]
}

module "alb_for_fargate" {
  source                     = "../"
  vpc_id                     = module.vpc.vpc_id
  public_subnet_ids          = module.vpc.public_subnets
  public_subnets_cidr_blocks = module.vpc.public_subnets_cidr_blocks
  route53_zone_id            = data.aws_route53_zone.selected.zone_id
  containers                 = local.containers

  access_logs_enabled = true
  access_logs_bucket = module.s3_bucket_for_logs.s3_bucket_id
  access_logs_prefix = "helloprefix"
}

#######################################
# ECS Service, task definition, ECR

module "ecs_service" {
  count = length(local.containers)
  source                 = "trussworks/ecs-service/aws"
  name                   = "${local.name_prefix}-${count.index}-${local.suffix}"
  environment            = local.suffix
  associate_alb          = true
  associate_nlb          = false
  alb_security_group     = module.alb_for_fargate.alb_security_group
  nlb_subnet_cidr_blocks = null

  lb_target_groups = [
    {
      lb_target_group_arn         = module.alb_for_fargate.lb_target_group_arns[count.index]
      container_port              = local.containers[count.index].backend_port
      container_health_check_port = local.containers[count.index].health_check_port
    },
  ]

  ecs_cluster                 = module.alb_for_fargate.aws_ecs_cluster
  ecs_subnet_ids              = module.vpc.public_subnets // TODO: when NAT is used, check that private subnets is availabled
  ecs_vpc_id                  = module.vpc.vpc_id
  ecs_use_fargate             = true
  assign_public_ip            = true
  kms_key_id                  = module.alb_for_fargate.kms_key_arn
  cloudwatch_alarm_cpu_enable = false
  cloudwatch_alarm_mem_enable = false
  target_container_name       = local.containers[count.index].name
  logs_cloudwatch_group       = local.containers[count.index].log_group_name
  fargate_task_memory         = 512
  fargate_task_cpu            = 256

  container_definitions       = jsonencode([{
    name      = local.containers[count.index].name
    image     = local.containers[count.index].image
    essential = true
    portMappings = [{
      containerPort = local.containers[count.index].backend_port
      hostPort      = local.containers[count.index].backend_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = local.containers[count.index].log_group_name
        "awslogs-region"        = local.region
        "awslogs-stream-prefix" = "main"
      }
    }
    mountPoints = []
    volumesFrom = []
    environment = [
      { name : "hello", value : "world" },
    ]
  }])
}

resource "aws_ecr_repository" "main" {
  name                 = "${local.name_prefix}-main-${local.suffix}"
  image_tag_mutability = "IMMUTABLE"
}

output "output" {
  description = "Resource information"
  value       = <<EOT
export ECR_REPOSITORY_URL=${aws_ecr_repository.main.repository_url}

EOT
}
