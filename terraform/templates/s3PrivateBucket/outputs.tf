output "abkPrivateS3BucketId" {
  description = "Private S3 Bucket ID"
  value       = aws_s3_bucket.abkPrivateS3Bucket.id
  sensitive   = true
}
