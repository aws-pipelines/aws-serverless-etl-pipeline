resource "aws_glue_catalog_database" "main" {
  name = replace("${var.app_name}_db", "-", "_")
}

# --- IAM role Glue crawlers/jobs run as -----------------------------------

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.app_name}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.raw.arn, "${aws_s3_bucket.raw.arn}/*",
      aws_s3_bucket.curated.arn, "${aws_s3_bucket.curated.arn}/*",
      aws_s3_bucket.scripts.arn, "${aws_s3_bucket.scripts.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "glue_s3" {
  name   = "${var.app_name}-glue-s3-policy"
  role   = aws_iam_role.glue.id
  policy = data.aws_iam_policy_document.glue_s3.json
}

# --- Crawlers ---------------------------------------------------------------

resource "aws_glue_crawler" "raw" {
  name          = "${var.app_name}-raw-crawler"
  database_name = aws_glue_catalog_database.main.name
  role          = aws_iam_role.glue.arn
  table_prefix  = "raw_"

  s3_target {
    path = "s3://${aws_s3_bucket.raw.id}/raw/orders/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_crawler" "curated" {
  name          = "${var.app_name}-curated-crawler"
  database_name = aws_glue_catalog_database.main.name
  role          = aws_iam_role.glue.arn
  table_prefix  = "curated_"

  s3_target {
    path = "s3://${aws_s3_bucket.curated.id}/curated/orders/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

# --- ETL job ----------------------------------------------------------------

resource "aws_glue_job" "transform" {
  name              = "${var.app_name}-transform"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 10 # minutes - the sample dataset is tiny
  max_retries       = 0

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.id}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--RAW_PATH"       = "s3://${aws_s3_bucket.raw.id}/raw/orders/"
    "--CURATED_PATH"   = "s3://${aws_s3_bucket.curated.id}/curated/orders/"
    "--TempDir"        = "s3://${aws_s3_bucket.scripts.id}/tmp/"
    "--job-language"   = "python"
    "--enable-metrics" = "true"
  }
}
