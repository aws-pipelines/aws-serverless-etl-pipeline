output "raw_bucket_name" {
  description = "Upload CSVs here (under raw/orders/) to trigger the pipeline."
  value       = aws_s3_bucket.raw.id
}

output "curated_bucket_name" {
  value = aws_s3_bucket.curated.id
}

output "glue_database_name" {
  value = aws_glue_catalog_database.main.name
}

output "state_machine_console_url" {
  description = "Watch pipeline runs here."
  value       = "https://${var.aws_region}.console.aws.amazon.com/states/home?region=${var.aws_region}#/statemachines/view/${aws_sfn_state_machine.pipeline.arn}"
}

output "query_gui_url" {
  description = "Open this URL in a browser to see the curated data."
  value       = aws_lambda_function_url.query_gui.function_url
}

output "athena_workgroup_name" {
  value = aws_athena_workgroup.main.name
}
