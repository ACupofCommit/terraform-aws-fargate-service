variable "name_prefix" {
  type        = string
  description = "For most of resource names"
}

variable "name_suffix" {
  type        = string
  description = "If omitted, random string is used."
  default     = ""
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 zone id for kibana_proxy_host"
}

variable "vpc_id" {
  type        = string
  description = "If you provide vpc_id, elasticsearch will be deployed in that vpc. Or it is distributed outside the vpc."
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "subnets_cidr_blocks" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "create_ecr" {
  type = bool
  default = true
}

variable "containers" {
  type = list(object({
    name              = string
    backend_port      = number
    health_check_port = number
    health_check_path = string
    domain            = string
  }))
}

variable "access_logs_enabled" {
  type = bool
  default = false
}
variable "access_logs_bucket" {
  type = string
  default = null
}
variable "access_logs_prefix" {
  type = string
  default = null
}
