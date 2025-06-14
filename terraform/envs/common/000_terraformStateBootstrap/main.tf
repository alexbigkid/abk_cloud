variable "abk_deployment_env" {
  type = string
}

variable "abk_deployment_region" {
  type = string
}

variable "terraform_state_S3_bucket_name" {
    type = string
}

variable "dynamodb_terraform_lock_name" {
    type = string
}

provider "aws" {
  region  = var.abk_deployment_region
}

module "terraformStateBootstrap" {
  source         = "../../../templates/terraformStateBootstrap"
  abk_deployment_env = var.abk_deployment_env
  abk_deployment_region = var.abk_deployment_region
  terraform_state_S3_bucket_name = var.terraform_state_S3_bucket_name
  dynamodb_terraform_lock_name = var.dynamodb_terraform_lock_name
}
