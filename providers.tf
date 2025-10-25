# provider.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Used for packaging the Lambda code locally
    archive = {
      source = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# DO NOT COMMIT SECRETS TO GIT!
# Using hardcoded values for a quick test based on user request.
# Best practice is to use profiles or environment variables.
provider "aws" {
  region     = "ap-south-1"
  access_key = "AKIAZ5TCxxxxxxxxxxx"
  secret_key = "xGxxxxxxxxxxxxxx"
}