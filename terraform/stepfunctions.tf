# --- IAM role the state machine runs as ------------------------------------

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.app_name}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "sfn_glue" {
  statement {
    effect = "Allow"
    actions = [
      "glue:StartCrawler",
      "glue:GetCrawler",
    ]
    resources = [aws_glue_crawler.raw.arn, aws_glue_crawler.curated.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]
    resources = [aws_glue_job.transform.arn]
  }
  statement {
    # Required by the .sync integration to receive job completion callbacks
    effect = "Allow"
    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule",
    ]
    resources = ["arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventForGlueStartJobRunRule"]
  }
}

resource "aws_iam_role_policy" "sfn_glue" {
  name   = "${var.app_name}-sfn-glue-policy"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn_glue.json
}

# --- State machine -----------------------------------------------------------

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${var.app_name}-pipeline"
  role_arn = aws_iam_role.sfn.arn

  definition = templatefile("${path.module}/../statemachine/pipeline.asl.json", {
    raw_crawler_name     = aws_glue_crawler.raw.name
    curated_crawler_name = aws_glue_crawler.curated.name
    glue_job_name        = aws_glue_job.transform.name
  })
}

# --- Trigger: new object in the raw bucket ----------------------------------

resource "aws_cloudwatch_event_rule" "raw_upload" {
  name = "${var.app_name}-raw-upload"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.raw.id] }
      object = { key = [{ prefix = "raw/orders/" }] }
    }
  })
}

data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_sfn" {
  name               = "${var.app_name}-eventbridge-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
}

resource "aws_iam_role_policy" "eventbridge_sfn" {
  name = "${var.app_name}-eventbridge-sfn-policy"
  role = aws_iam_role.eventbridge_sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = aws_sfn_state_machine.pipeline.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "pipeline" {
  rule     = aws_cloudwatch_event_rule.raw_upload.name
  arn      = aws_sfn_state_machine.pipeline.arn
  role_arn = aws_iam_role.eventbridge_sfn.arn
}
