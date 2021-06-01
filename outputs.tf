output "alb_security_group" {
  value = module.alb_security_group.security_group_id
}

output "lb_target_group_arns" {
  value = module.alb.target_group_arns
}

output "aws_ecs_cluster" {
  value = aws_ecs_cluster.main
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}
