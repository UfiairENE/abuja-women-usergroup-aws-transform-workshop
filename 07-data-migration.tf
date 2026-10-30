# EXPERIMENTAL and untested, off by default. A pretend "on-premises" SQL Server and an AWS DMS task that copies its rows into Aurora.
# This is the only public piece of the stack: the SQL Server source sits in two public subnets so you can load
# a row into it from your laptop, and only your IP (source_allowed_cidr) can reach it. Aurora stays private.
# Turn on with enable_data_migration = true and source_allowed_cidr = "<your ip>/32".

locals {
  dm = var.enable_data_migration ? 1 : 0
}

# ── Public subnets for the source only ───────────────────────────────────────
resource "aws_internet_gateway" "source" {
  count  = local.dm
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-source" }
}

resource "aws_subnet" "public" {
  count             = var.enable_data_migration ? 2 : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 100 + count.index)
  availability_zone = var.availability_zones[count.index]
  tags              = { Name = "${local.name}-public-${var.availability_zones[count.index]}" }
}

resource "aws_route_table" "public" {
  count  = local.dm
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-public" }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.source[0].id
  }
}

resource "aws_route_table_association" "public" {
  count          = var.enable_data_migration ? 2 : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# ── The SQL Server source (Express edition, smallest size) ───────────────────
resource "aws_db_subnet_group" "source" {
  count      = local.dm
  name       = "${local.name}-source"
  subnet_ids = aws_subnet.public[*].id
}

resource "aws_security_group" "source" {
  count       = local.dm
  name        = "${local.name}-source"
  description = "SQL Server source: 1433 from your IP and from DMS"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "source_from_me" {
  count             = local.dm
  security_group_id = aws_security_group.source[0].id
  cidr_ipv4         = var.source_allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 1433
  to_port           = 1433
}

resource "aws_vpc_security_group_ingress_rule" "source_from_dms" {
  count                        = local.dm
  security_group_id            = aws_security_group.source[0].id
  referenced_security_group_id = aws_security_group.dms[0].id
  ip_protocol                  = "tcp"
  from_port                    = 1433
  to_port                      = 1433
}

data "aws_rds_engine_version" "sqlserver" {
  count        = local.dm
  engine       = "sqlserver-ex"
  default_only = true
}

resource "aws_db_instance" "source" {
  count                  = local.dm
  identifier             = "${local.name}-source"
  engine                 = "sqlserver-ex"
  engine_version         = data.aws_rds_engine_version.sqlserver[0].version
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  license_model          = "license-included"
  username               = "sqladmin"
  db_subnet_group_name   = aws_db_subnet_group.source[0].name
  vpc_security_group_ids = [aws_security_group.source[0].id]
  publicly_accessible    = true
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.main.arn
  skip_final_snapshot    = true
  apply_immediately      = true

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.arn
}

# ── AWS DMS ──────────────────────────────────────────────────────────────────
# DMS needs an account-level role with exactly this name. If your account already has it, set
# create_dms_vpc_role = false below.
resource "aws_iam_role" "dms_vpc" {
  count = local.dm
  name  = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dms.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  count      = local.dm
  role       = aws_iam_role.dms_vpc[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_security_group" "dms" {
  count       = local.dm
  name        = "${local.name}-dms"
  description = "DMS replication instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "dms_to_source" {
  count                        = local.dm
  security_group_id            = aws_security_group.dms[0].id
  referenced_security_group_id = aws_security_group.source[0].id
  ip_protocol                  = "tcp"
  from_port                    = 1433
  to_port                      = 1433
}

resource "aws_vpc_security_group_egress_rule" "dms_to_aurora" {
  count                        = local.dm
  security_group_id            = aws_security_group.dms[0].id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "db_from_dms" {
  count                        = local.dm
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.dms[0].id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_dms_replication_subnet_group" "main" {
  count                                = local.dm
  replication_subnet_group_id          = local.name
  replication_subnet_group_description = "Private subnets for the DMS replication instance"
  subnet_ids                           = aws_subnet.private[*].id
  depends_on                           = [aws_iam_role_policy_attachment.dms_vpc]
}

resource "aws_dms_replication_instance" "main" {
  count                       = local.dm
  replication_instance_id     = local.name
  replication_instance_class  = "dms.t3.micro"
  allocated_storage           = 20
  multi_az                    = false
  publicly_accessible         = false
  replication_subnet_group_id = aws_dms_replication_subnet_group.main[0].id
  vpc_security_group_ids      = [aws_security_group.dms[0].id]
  apply_immediately           = true
}

# Passwords come from the Secrets Manager secrets RDS manages for each database
data "aws_secretsmanager_secret_version" "source" {
  count     = local.dm
  secret_id = aws_db_instance.source[0].master_user_secret[0].secret_arn
}

data "aws_secretsmanager_secret_version" "target" {
  count     = local.dm
  secret_id = aws_rds_cluster.main.master_user_secret[0].secret_arn
}

resource "aws_dms_endpoint" "source" {
  count         = local.dm
  endpoint_id   = "${local.name}-source"
  endpoint_type = "source"
  engine_name   = "sqlserver"
  server_name   = aws_db_instance.source[0].address
  port          = 1433
  database_name = "RetailDemo"
  username      = "sqladmin"
  password      = jsondecode(data.aws_secretsmanager_secret_version.source[0].secret_string)["password"]
  ssl_mode      = "none"
}

resource "aws_dms_endpoint" "target" {
  count         = local.dm
  endpoint_id   = "${local.name}-target"
  endpoint_type = "target"
  engine_name   = "aurora-postgresql"
  server_name   = aws_rds_cluster.main.endpoint
  port          = 5432
  database_name = var.db_name
  username      = "postgres_admin"
  password      = jsondecode(data.aws_secretsmanager_secret_version.target[0].secret_string)["password"]
  ssl_mode      = "require"
}

# The converted schema already exists in Aurora, so DMS only copies rows (DO_NOTHING),
# and renames sales.Customer to retaildemo_sales.customer, all lowercase, like Transform did.
resource "aws_dms_replication_task" "main" {
  count                    = local.dm
  replication_task_id      = local.name
  migration_type           = "full-load"
  replication_instance_arn = aws_dms_replication_instance.main[0].replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source[0].endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target[0].endpoint_arn
  start_replication_task   = false

  replication_task_settings = jsonencode({
    FullLoadSettings = { TargetTablePrepMode = "DO_NOTHING" }
  })

  table_mappings = jsonencode({
    rules = [
      { "rule-type" = "selection", "rule-id" = "1", "rule-name" = "include-sales", "rule-action" = "include",
      "object-locator" = { "schema-name" = "sales", "table-name" = "%" } },
      { "rule-type" = "transformation", "rule-id" = "2", "rule-name" = "rename-schema", "rule-action" = "rename",
      "rule-target" = "schema", "value" = "retaildemo_sales", "object-locator" = { "schema-name" = "sales" } },
      { "rule-type" = "transformation", "rule-id" = "3", "rule-name" = "lowercase-tables", "rule-action" = "convert-lowercase",
      "rule-target" = "table", "object-locator" = { "schema-name" = "sales", "table-name" = "%" } },
      { "rule-type" = "transformation", "rule-id" = "4", "rule-name" = "lowercase-columns", "rule-action" = "convert-lowercase",
      "rule-target" = "column", "object-locator" = { "schema-name" = "sales", "table-name" = "%", "column-name" = "%" } },
    ]
  })
}
