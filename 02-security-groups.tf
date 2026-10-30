# Attach to anything that needs to reach the database
resource "aws_security_group" "client" {
  name        = "${local.name}-client"
  description = "Clients allowed to reach Aurora PostgreSQL"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "Aurora PostgreSQL: 5432 from client SG only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_client" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.client.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
