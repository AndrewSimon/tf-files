provider "aws" {
## Terraform can find aws creds in ~/.aws directory
## Github creds are manually stored in SSM parameter store
  region     = "us-east-1"
}

terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket = "technology-leadership-terraform-state"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "local" {}

# Github Personal Access Token is an SSM parameter store secret (needed for the provider)
data "aws_ssm_parameter" "gh_pat" {
      name = "gh_pat"
      with_decryption = true
}

provider "github" {
  token        = "${data.aws_ssm_parameter.gh_pat.value}"
}

# public_key is optional if/when using key_name
resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}" 
}
