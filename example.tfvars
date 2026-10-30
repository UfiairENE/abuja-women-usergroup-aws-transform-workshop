# Copy to workshop.tfvars (git-ignored) and adjust. Used by `just plan` / `just workshop`.
# Pick any region; availability_zones must belong to it.

project     = "transform-mssql-aurora"
environment = "workshop"
aws_region  = "eu-west-2"

# Networking — private only, no IGW / NAT
vpc_cidr             = "10.42.0.0/16"
availability_zones   = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
private_subnet_cidrs = ["10.42.0.0/24", "10.42.1.0/24", "10.42.2.0/24"]

# Aurora PostgreSQL — smallest class, writer + reader across AZs
db_instance_class        = "db.t4g.medium"
db_instance_count        = 2
db_name                  = "workshop"
db_backup_retention_days = 7
db_monitoring_interval   = 60


# Optional: small private instance for loading the converted schema (Session Manager)
enable_ssm_client = true
