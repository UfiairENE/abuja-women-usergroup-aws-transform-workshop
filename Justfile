# Auth: `just login` saves a Terraform Cloud token to .tfc.env (git-ignored), which
# just loads for every recipe. This leaves ~/.terraform.d untouched, so it won't
# change your `terraform login` for other projects. Without .tfc.env, run
# `terraform login` or export TF_TOKEN_app_terraform_io instead.
# AWS access comes from Terraform Cloud OIDC (workspace env vars
# TFC_AWS_PROVIDER_AUTH + TFC_AWS_RUN_ROLE_ARN) — no local AWS keys.

set dotenv-filename := ".tfc.env"
set dotenv-load

login:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Create a token at https://app.terraform.io/app/settings/tokens"
    echo "(signed in as the account that owns your org), then paste it here."
    read -rsp "Token: " token; echo
    umask 077
    printf 'TF_TOKEN_app_terraform_io=%s\n' "$token" > .tfc.env
    echo "Saved to .tfc.env"

workshop:
    TF_WORKSPACE=workshop-aurora-pg terraform init
    TF_WORKSPACE=workshop-aurora-pg terraform plan -var-file=workshop.tfvars
    TF_WORKSPACE=workshop-aurora-pg terraform apply -var-file=workshop.tfvars

plan:
    TF_WORKSPACE=workshop-aurora-pg terraform init
    TF_WORKSPACE=workshop-aurora-pg terraform plan -var-file=workshop.tfvars

destroy:
    TF_WORKSPACE=workshop-aurora-pg terraform destroy -var-file=workshop.tfvars

fmt:
    terraform fmt -recursive

bootstrap:
    cd bootstrap && terraform init && terraform apply
