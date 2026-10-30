terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  cloud {
    organization = "abj-aws-ug"

    workspaces {
      name = "workshop-aurora-pg"
    }
  }
}

# No static AWS credentials. Terraform Cloud assumes the role in
# TFC_AWS_RUN_ROLE_ARN via OIDC (see bootstrap/).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Purpose     = "workshop"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

locals {
  name = "${var.project}-${var.environment}"
}
