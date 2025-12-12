variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-east-1"
}

variable "aws_az" {
  description = "AWS AZ to launch servers."
  default     = "us-east-1f"
}

variable "public_key_path" {
  description = "Path to the authorized keys file"
  default = "C:/Users/asimon/.ssh/authorized_keys"
}

variable "key_name" {
  description = "AWS Work"
  default = "AWS Work"
}

variable "instance_type" {
  description = "Instance Type"
  default = "t3a.micro"
}

variable "ami_id" {
  description = "The AMI ID for the EC2 instance."
  type        = string
  default = "ami-0424b6c6518fafbaf"
}

# CIDRs are stashed in SSM parameter store
#variable "cidr_blocks" {
# description = "List of CIDR blocks allowed for ingress rules."
# type        = list(string)

