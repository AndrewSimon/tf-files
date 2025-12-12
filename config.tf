provider "aws" {
## Use OIDC instead
#  access_key = "XXXXXXXXXXXXXXXXXXXX"
#  secret_key = "1234567890abcdefghijklmnopqrstuvwxyz+ABCDE"
  region     = "us-east-1"
}

terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
  }
  backend "s3" {
    bucket = "technology-leadership-terraform-state"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "local" {}

# Specify file path in variables.tf or replace var with pub key material here
resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}" 
}
