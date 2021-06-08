# terraform-aws-fargate-service
Provides one or more ecs fargate services through one ALB and domain.

## Update ecs task definition
1. Taint terraform task definition state then apply it. Example:

```
$ terraform taint module.module-name.aws_ecs_task_definition.main
$ terraform apply
```

> Alternatively, you can manually update it from the AWS Console.

2. Go AWS ECS Console, select cluster - Service - `Update`
   then select the latest task definition

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.14.0 |
| aws | ~> 3.0 |
| random | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| aws | ~> 3.0 |
| random | ~> 3.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| access\_logs\_bucket | n/a | `string` | `null` | no |
| access\_logs\_enabled | n/a | `bool` | `false` | no |
| access\_logs\_prefix | n/a | `string` | `null` | no |
| alb\_egress\_cidrs | n/a | `list(string)` | n/a | yes |
| containers | n/a | <pre>list(object({<br>    name              = string<br>    backend_port      = number<br>    health_check_port = number<br>    health_check_path = string<br>    domain            = string<br>  }))</pre> | n/a | yes |
| create\_ecr | n/a | `bool` | `true` | no |
| name\_prefix | For most of resource names | `string` | n/a | yes |
| name\_suffix | If omitted, random string is used. | `string` | `""` | no |
| route53\_zone\_id | Route53 zone id for kibana\_proxy\_host | `string` | n/a | yes |
| subnet\_ids | n/a | `list(string)` | `[]` | no |
| tags | n/a | `map(string)` | `{}` | no |
| vpc\_id | If you provide vpc\_id, elasticsearch will be deployed in that vpc. Or it is distributed outside the vpc. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| alb\_security\_group | n/a |
| aws\_ecs\_cluster | n/a |
| kms\_key\_arn | n/a |
| lb\_target\_group\_arns | n/a |
