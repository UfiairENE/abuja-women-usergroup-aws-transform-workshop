# One-time: creates the IAM role Terraform Cloud assumes via OIDC for the
# workshop workspace. Apply from CloudShell / any admin session, then delete
# the role after the workshop. Reuses the account's existing TFC OIDC provider.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1" # IAM is global; region is irrelevant
}

variable "tfc_organization" {
  type    = string
  default = "abj-aws-ug"
}

variable "tfc_workspace" {
  type    = string
  default = "workshop-aurora-pg"
}

data "aws_iam_openid_connect_provider" "tfc" {
  url = "https://app.terraform.io"
}

resource "aws_iam_role" "workshop" {
  name = "tfc-oidc-workshop"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.tfc.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "app.terraform.io:aud" = "aws.workload.identity" }
        StringLike = {
          "app.terraform.io:sub" = "organization:${var.tfc_organization}:project:*:workspace:${var.tfc_workspace}:run_phase:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "workshop" {
  role       = aws_iam_role.workshop.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "role_arn" {
  value = aws_iam_role.workshop.arn
}

# Paste these two into the Terraform Cloud workspace as environment variables (not Terraform variables).
output "tfc_environment_variables" {
  value = {
    TFC_AWS_PROVIDER_AUTH = "true"
    TFC_AWS_RUN_ROLE_ARN  = aws_iam_role.workshop.arn
  }
}
