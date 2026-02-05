variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-east-1"
}

variable "vpc_name" {
  description = "AWS VPC Name"
  default     = "test2"
}

# Not used in this demo, but current coding expects it
variable "public_key_path" {
  description = "Path to the authorized keys file"
  default = "C:/Users/asimon/.ssh/authorized_keys"
}

variable "key_name" {
  description = "AWS Work"
  default = "AWS Work"
}

## The two variables below enable toggle between standing up a new VPC or using existing VPC
## It defaults to stand-up a new VPC as it assumes you are running this the first time
## If you are importing a VPC or keeping the one you previously created, you must set this 
## to false AND specify the default vpc-id in the variable vpc_id below 
## or remember to do the command-line overrides -var="create_vpc=false" -var="vpc_id=vpc-123456780"

variable "create_vpc" {
  description = "Set to create a new one, otherwise set to false."
  type        = bool
  default     = true
}

# If/when the VPC is created and you are not destroying it, add the VPC-ID below
variable "vpc_id" {
  description = "The ID of an existing VPC (if use_existing_vpc is true)."
  type        = string
  default     = ""
}

#### Variables below are for boto3 run_instances, not terraform's aws_instance resource 
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

variable "instance_type" {
  description = "Instance Type"
  default = "t3.micro"
}

variable "ami_id" {
  description = "Subscribe to https://aws.amazon.com/marketplace/pp/prodview-zsmcixdrlp2ti for the correct AMI ID."
  type        = string
  default = "ami-00105ec16deadf5b2" # This may not be the Marketplace AMI ID in our region
}

variable "spot_market" {
  description = "Python boolean must be uppercase first letter. Thus, a string in terraform. Set to False to request an on-demand instance."
  type        = string
  default     = "True"
}

variable "volume_size" {
  description = "Size in GB. The TLC AMI is only 14, increase as needed"
  type        = string
  default     = "14"
}

variable "instance_profile" {
  description = "Use the ssm_profile we built in ssm.tf or override with your own"
  type        = string
  default     = "spot_instance_profile"
}

variable "max_instances" {
description = "Maximum number of running instances allowed by lambda_handler. Keep high if terminating instances at completion"
  type        = string
  default     = "10"
}

variable "repo_name" {
  description = "Change below to push/pull from your repo"
  type        = string
  default     = "AndrewSimon/tf-files"
}