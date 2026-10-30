resource "aws_kms_key" "main" {
  description             = "${local.name} encryption key (Aurora storage and its Secrets Manager secret)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}
