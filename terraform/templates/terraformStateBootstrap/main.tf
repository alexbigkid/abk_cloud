resource "aws_s3_bucket" "abkTerraformStateS3Bucket" {
  bucket = "${var.terraform_state_S3_bucket_name}"
}

resource "aws_s3_bucket_versioning" "abkTerraformStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformStateS3Bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "abkTerraformStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformStateS3Bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_s3_bucket_acl" "abkTerraformStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformStateS3Bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "abkTerraformStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformStateS3Bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "abkDynamodbTerraformLock" {
  name           = "${var.dynamodb_terraform_lock_name}"
  hash_key       = "LockID"
  read_capacity  = 20
  write_capacity = 20
#   billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    env = "${var.abk_deployment_env}"
    region = "${var.abk_deployment_region}"
  }
}
