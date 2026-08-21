# Public, click-to-browse GUI for the curated data - a Lambda Function URL
# that runs one fixed Athena query and renders the results as an HTML table.

data "archive_file" "query_app" {
  type        = "zip"
  source_file = "${path.module}/../query_app/handler.py"
  output_path = "${path.module}/../query_app/build/query_app.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "query_gui" {
  name               = "${var.app_name}-query-gui-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "query_gui_logs" {
  role       = aws_iam_role.query_gui.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "query_gui" {
  statement {
    sid    = "AthenaQuery"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
    ]
    resources = [aws_athena_workgroup.main.arn]
  }
  statement {
    sid    = "GlueCatalogRead"
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetDatabase",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
      aws_glue_catalog_database.main.arn,
      "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.main.name}/*",
    ]
  }
  statement {
    sid       = "ReadCuratedData"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.curated.arn, "${aws_s3_bucket.curated.arn}/*"]
  }
  statement {
    sid       = "AthenaResults"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.athena_results.arn, "${aws_s3_bucket.athena_results.arn}/*"]
  }
}

resource "aws_iam_role_policy" "query_gui" {
  name   = "${var.app_name}-query-gui-policy"
  role   = aws_iam_role.query_gui.id
  policy = data.aws_iam_policy_document.query_gui.json
}

resource "aws_lambda_function" "query_gui" {
  function_name    = "${var.app_name}-query-gui"
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  role             = aws_iam_role.query_gui.arn
  filename         = data.archive_file.query_app.output_path
  source_code_hash = data.archive_file.query_app.output_base64sha256
  timeout          = 35
  memory_size      = 256

  environment {
    variables = {
      GLUE_DATABASE    = aws_glue_catalog_database.main.name
      CURATED_TABLE    = "curated_orders"
      ATHENA_WORKGROUP = aws_athena_workgroup.main.name
    }
  }
}

resource "aws_lambda_function_url" "query_gui" {
  function_name      = aws_lambda_function.query_gui.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "query_gui_public" {
  function_name          = aws_lambda_function.query_gui.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}
