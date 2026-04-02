terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — reuses the existing achille-tf-state S3 bucket
  # Each project uses a different key so state files are isolated
  # DynamoDB table provides state locking — prevents concurrent applies
  backend "s3" {
    bucket         = "achille-tf-state"
    key            = "devops-platform-lab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devops-platform-lab-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
