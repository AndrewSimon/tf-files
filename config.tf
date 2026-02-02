provider "aws" {
## Terraform can find aws creds in ~/.aws directory
## Github creds are manually stored in SSM parameter store
  region     = "${var.aws_region}"
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
    # export your BUCKET_NAME and set TF_CLI_ARGS_init or hard-code
#    bucket = "technology-leadership-terraform-state"
    key    = "terraform.tfstate"
    # export your AWS_REGION and set TF_CLI_ARGS_init or hard-code
#    region = "${var.aws_region}"
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
