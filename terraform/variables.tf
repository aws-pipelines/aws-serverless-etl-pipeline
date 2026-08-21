variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy into."
}

variable "app_name" {
  type        = string
  default     = "etl-demo"
  description = "Prefix used to name all created resources."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.app_name))
    error_message = "app_name must be 3-21 lowercase letters, numbers, or hyphens, starting with a letter."
  }
}
