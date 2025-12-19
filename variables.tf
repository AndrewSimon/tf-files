variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-east-1"
}

variable "vpc_name" {
  description = "AWS VPC Name"
  default     = "test2"
}

# Use any 'f' AZ below, but if your region does not have an 'f' AZ
# update main.tf and lambda.tf, accordingly
variable "aws_az" {
  description = "AWS Availability Zone"
  default     = "us-east-1f"
}

variable "aws_subnet_tag" {
  description = "AWS Availability Zone"
  default     = "Public_1F"
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
  description = "Please subscribe to this TLC AMI ID for the EC2 instance before using tf."
  type        = string
  default = "ami-04398049c37e2ad5a"
}