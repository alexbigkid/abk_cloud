# -----------------------------------------------------------------------------
# definitions and Terraform backend
# -----------------------------------------------------------------------------
locals {
  common_tags = {
    env = "${var.abk_deployment_env}"
  }
}

provider "aws" {
  region = var.abk_deployment_region
}

terraform {
  backend "s3" {
    bucket = var.terraform_state_S3_bucket_name
    key    = "${var.abk_deployment_env}/${var.abk_service_deployment_bucket_name}/terraform.tfstate"
    region = var.abk_deployment_region

    dynamodb_table = var.dynamodb_terraform_lock_name
    encrypt        = true
  }
}


# -----------------------------------------------------------------------------
# modules
# -----------------------------------------------------------------------------
module "abk_s3_releases_bucket_module" {
  source                 = "../../../templates/s3-private-bucket"
  private_s3_bucket_name = var.abk_service_deployment_bucket_name
  enable_versioning      = var.enable_versioning
}
