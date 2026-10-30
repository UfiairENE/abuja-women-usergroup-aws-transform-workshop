variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

# ── VPC / Networking ─────────────────────────────────────────────────────────
variable "vpc_cidr" { type = string }

variable "availability_zones" {
  type        = list(string)
  description = "AZs for private subnets, one subnet per AZ"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDRs for private DB subnets, one per AZ"
}

# ── Aurora PostgreSQL ────────────────────────────────────────────────────────
variable "db_instance_class" {
  type        = string
  description = "Smallest class supported by Aurora PostgreSQL is db.t4g.medium"
}

variable "db_instance_count" {
  type        = number
  description = "1 writer + N-1 readers"
}

variable "db_name" { type = string }

variable "db_backup_retention_days" { type = number }

variable "db_monitoring_interval" {
  type        = number
  description = "Enhanced Monitoring interval in seconds"
}

# ── Optional client instance ─────────────────────────────────────────────────
variable "enable_ssm_client" {
  type        = bool
  default     = false
  description = "Create a small private instance reachable with Session Manager, for running psql against Aurora"
}
