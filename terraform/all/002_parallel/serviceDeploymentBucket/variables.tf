variable "abk_deployment_env" {
  description = "Deployment environment: dev, qa, or prod"
  type        = string
}

variable "abk_deployment_region" {
  description = "Deployment region: we run at the moment only on us-west-2"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to some of the AWS items. It should be a map (key: value) variable."
  type        = map(any)
}

variable "terraform_state_S3_bucket_name" {
  description = "terraform state S3 bucket name"
  type        = string
  sensitive   = true
}

variable "abk_service_deployment_bucket_name" {
  description = "s3 bucket name for service deployments"
  type        = string
  sensitive   = true
}
