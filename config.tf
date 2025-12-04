provider "aws" {
## We set these with ENV variables, no need to set them in IaC
#  access_key = "XXXXXXXXXXXXXXXXXXXX"
#  secret_key = "1234567890abcdefghijklmnopqrstuvwxyz+ABCDE"
  region     = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "technology-leadership-terraform-state"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

# Specify file path in variables.tf or replace var with pub key material here
resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}" 
}
