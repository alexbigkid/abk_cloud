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
  depends_on = [aws_s3_bucket_ownership_controls.abkTerraformStateS3Bucket]
  bucket = aws_s3_bucket.abkTerraformStateS3Bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_ownership_controls" "abkTerraformStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformStateS3Bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "abkTerraformStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformStateS3Bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bootstrap state bucket (for storing bootstrap terraform state)
resource "aws_s3_bucket" "abkTerraformBootstrapStateS3Bucket" {
  bucket = "${var.terraform_bootstrap_state_s3_bucket}"
}

resource "aws_s3_bucket_versioning" "abkTerraformBootstrapStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformBootstrapStateS3Bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "abkTerraformBootstrapStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformBootstrapStateS3Bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_s3_bucket_acl" "abkTerraformBootstrapStateS3Bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.abkTerraformBootstrapStateS3Bucket]
  bucket = aws_s3_bucket.abkTerraformBootstrapStateS3Bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_ownership_controls" "abkTerraformBootstrapStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformBootstrapStateS3Bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "abkTerraformBootstrapStateS3Bucket" {
  bucket = aws_s3_bucket.abkTerraformBootstrapStateS3Bucket.id

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
