variable "abk_deployment_env" {
    description = "Environment to deploy to: dev, qa or prod."
    type = string

    validation {
        condition     = var.abk_deployment_env == "dev" || var.abk_deployment_env == "qa" || var.abk_deployment_env == "prod"
        error_message = "The abk_deployment_env value must be a valid string: dev, qa or prod."
    }
}

variable "abk_deployment_region" {
    description = "AWS deployment region."
    type = string

    validation {
        condition     = var.abk_deployment_region == "us-west-2"
        error_message = "The abk_deployment_region value must be a valid string: ATM only us-west-2."
    }
}

variable "terraform_state_S3_bucket_name" {
    description = "Name of Terraform State S3 bucket."
    type = string
}

variable "dynamodb_terraform_lock_name" {
    description = "Name of DynamoDB table to use for Terraform state locking."
    type = string
}
