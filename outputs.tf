output "region" { value = var.aws_region }
output "writer_endpoint" { value = aws_rds_cluster.main.endpoint }
output "reader_endpoint" { value = aws_rds_cluster.main.reader_endpoint }
output "secret_arn" { value = aws_rds_cluster.main.master_user_secret[0].secret_arn }
output "client_sg_id" { value = aws_security_group.client.id }
output "ssm_client_instance_id" { value = var.enable_ssm_client ? aws_instance.ssm_client[0].id : null }
