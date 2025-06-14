# -----------------------------------------------------------------------------
# Private S3 bucket module
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "abkPrivateS3Bucket" {
  bucket = var.private_s3_bucket_name

  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "abkPrivateS3BucketVersioning" {
  bucket = aws_s3_bucket.abkPrivateS3Bucket.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "abkPrivateS3BucketServerSideEncryptionConfiguration" {
  bucket = aws_s3_bucket.abkPrivateS3Bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "abkPrivateS3BucketOwnershipControls" {
  bucket = aws_s3_bucket.abkPrivateS3Bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "abkPrivateS3BucketPublicAccessBlock" {
  bucket = aws_s3_bucket.abkPrivateS3Bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
