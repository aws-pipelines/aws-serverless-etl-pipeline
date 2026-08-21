data "aws_caller_identity" "current" {}

locals {
  bucket_suffix = "${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "raw" {
  bucket = "${var.app_name}-raw-${local.bucket_suffix}"
}

resource "aws_s3_bucket" "curated" {
  bucket = "${var.app_name}-curated-${local.bucket_suffix}"
}

resource "aws_s3_bucket" "scripts" {
  bucket = "${var.app_name}-scripts-${local.bucket_suffix}"
}

resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.app_name}-athena-results-${local.bucket_suffix}"
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    id     = "expire-query-results"
    status = "Enabled"
    filter {}
    expiration {
      days = 7
    }
  }
}

# Native S3 -> EventBridge notifications (no CloudTrail needed) so the
# Step Functions state machine can trigger on new raw uploads.
resource "aws_s3_bucket_notification" "raw" {
  bucket      = aws_s3_bucket.raw.id
  eventbridge = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "all" {
  for_each = {
    raw            = aws_s3_bucket.raw.id
    curated        = aws_s3_bucket.curated.id
    scripts        = aws_s3_bucket.scripts.id
    athena_results = aws_s3_bucket.athena_results.id
  }
  bucket = each.value
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "all" {
  for_each = {
    raw            = aws_s3_bucket.raw.id
    curated        = aws_s3_bucket.curated.id
    scripts        = aws_s3_bucket.scripts.id
    athena_results = aws_s3_bucket.athena_results.id
  }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.scripts.id
  key    = "scripts/transform.py"
  source = "${path.module}/../glue_jobs/transform.py"
  etag   = filemd5("${path.module}/../glue_jobs/transform.py")
}

# Seed sample data so the pipeline has something to process immediately
# after `terraform apply` - upload your own CSVs alongside/instead of this.
resource "aws_s3_object" "sample_data" {
  bucket = aws_s3_bucket.raw.id
  key    = "raw/orders/orders_sample.csv"
  source = "${path.module}/../data/orders_sample.csv"
  etag   = filemd5("${path.module}/../data/orders_sample.csv")

  # Best-effort: try to have the EventBridge rule in place before this
  # upload fires its Object Created event. Not guaranteed - if the first
  # pipeline run doesn't start automatically, just re-upload the file
  # (or any CSV) through the S3 console to trigger it manually.
  depends_on = [aws_cloudwatch_event_target.pipeline]
}
