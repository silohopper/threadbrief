terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# CloudFront requires viewer certificates to live in us-east-1, regardless of
# where the rest of the stack runs.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
