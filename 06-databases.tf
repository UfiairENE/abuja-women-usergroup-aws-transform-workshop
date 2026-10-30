data "aws_rds_engine_version" "aurora_postgresql" {
  engine       = "aurora-postgresql"
  default_only = true
}

resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_rds_cluster" "main" {
  cluster_identifier = local.name
  engine             = "aurora-postgresql"
  engine_version     = data.aws_rds_engine_version.aurora_postgresql.version
  database_name      = var.db_name
  master_username    = "postgres_admin"

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.arn

  storage_encrypted      = true
  kms_key_id             = aws_kms_key.main.arn
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  iam_database_authentication_enabled = true
  backup_retention_period             = var.db_backup_retention_days
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  # Deletion protection is on. Turn it off in the console (Modify cluster) before
  # `just destroy`, or set it to false here and apply first.
  skip_final_snapshot = true
  deletion_protection = true
  apply_immediately   = true
}

# One writer and N-1 readers, spread across AZs. Aurora picks which instance is the writer when the
# cluster is created, and it can change after a failover, so do not assume index 0 is the writer.
resource "aws_rds_cluster_instance" "main" {
  count               = var.db_instance_count
  identifier          = "${local.name}-${count.index}"
  cluster_identifier  = aws_rds_cluster.main.id
  engine              = aws_rds_cluster.main.engine
  engine_version      = aws_rds_cluster.main.engine_version
  instance_class      = var.db_instance_class
  availability_zone   = var.availability_zones[count.index % length(var.availability_zones)]
  publicly_accessible = false
  promotion_tier      = count.index

  monitoring_interval = var.db_monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}
