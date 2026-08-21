terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Local backend by default so this repo works out of the box.
  # For real use, switch to an S3 backend with state locking:
  # backend "s3" {
  #   bucket       = "<your-tfstate-bucket>"
  #   key          = "aws-serverless-etl-pipeline/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region
}
