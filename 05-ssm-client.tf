# Optional: a tiny private instance you reach with Session Manager (no SSH, no public IP,
# no internet). Use it to run psql against Aurora and load the converted schema.
# Turn on with enable_ssm_client = true.

locals {
  ssm_endpoints = var.enable_ssm_client ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])
}

resource "aws_iam_role" "ssm_client" {
  count = var.enable_ssm_client ? 1 : 0
  name  = "${local.name}-ssm-client"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_client" {
  count      = var.enable_ssm_client ? 1 : 0
  role       = aws_iam_role.ssm_client[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_client" {
  count = var.enable_ssm_client ? 1 : 0
  name  = "${local.name}-ssm-client"
  role  = aws_iam_role.ssm_client[0].name
}

# Session Manager needs these three endpoints because the VPC has no internet route
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_ssm_client ? 1 : 0
  name        = "${local.name}-vpc-endpoints"
  description = "HTTPS from the client SG to the Session Manager endpoints"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_client" {
  count                        = var.enable_ssm_client ? 1 : 0
  security_group_id            = aws_security_group.vpc_endpoints[0].id
  referenced_security_group_id = aws_security_group.client.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = local.ssm_endpoints
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true
  tags                = { Name = "${local.name}-${each.key}" }
}

# The client SG has no egress by default, so give it exactly what the instance needs
resource "aws_vpc_security_group_egress_rule" "client_to_db" {
  count                        = var.enable_ssm_client ? 1 : 0
  security_group_id            = aws_security_group.client.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "client_to_endpoints" {
  count                        = var.enable_ssm_client ? 1 : 0
  security_group_id            = aws_security_group.client.id
  referenced_security_group_id = aws_security_group.vpc_endpoints[0].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# Package repositories for Amazon Linux are served from S3
resource "aws_vpc_security_group_egress_rule" "client_to_s3" {
  count             = var.enable_ssm_client ? 1 : 0
  security_group_id = aws_security_group.client.id
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

data "aws_ssm_parameter" "al2023_arm64" {
  count = var.enable_ssm_client ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "ssm_client" {
  count                  = var.enable_ssm_client ? 1 : 0
  ami                    = data.aws_ssm_parameter.al2023_arm64[0].value
  instance_type          = "t4g.nano"
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.client.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_client[0].name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = { Name = "${local.name}-ssm-client" }

  depends_on = [aws_vpc_endpoint.ssm]
}
