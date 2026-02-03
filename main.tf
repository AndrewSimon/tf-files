## Terraform main
## The key word 'resource' creates resources if not already imported
## Trying to create a resource with an existing name fails
## Order is not important, but in this case:
## 1) Create VPC and VPC components - comment out Public_F if your region does not have an 'f' AZ
## 2) Get the SSM parameter store value for undisclosed resource values
## 3) Create a Security Group
## 4) Create a key pair - commented as we'll use existing key
## 5) Instantiate one generic on-demand server (i.e. not the lambda created ephemeral spot runner)
## 6) As part of instantiation, assign the sg created earlier and add a public IP

# Create a VPC to launch our instances into, must be hard-coded
# Change "test2" to whatever you changed vpc_name to in varialbes.tf
resource "aws_vpc" "test2" {
  cidr_block = "192.168.10.0/24"
  enable_dns_hostnames = "true"
  tags                    = {
     "Name" = var.vpc_name 
     }
}

# Get the name of the vpc we're using for later interpolation
data "aws_vpc" "selected" {
  tags = {
    Name = var.vpc_name
  }
   depends_on = [
     aws_vpc.test2
  ]
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "gw1" {
   vpc_id = data.aws_vpc.selected.id
   
   tags   = {
       "Name" = "gw1"
   }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = data.aws_vpc.selected.id
  # Grant the VPC internet access on its main route table
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw1.id}"
  }
  tags = {
    Name = "rt-${var.vpc_name}"
  }
}

# Example single route entry = not needed as was added above
# Grant the VPC internet access on its main route table
# resource "aws_route" "internet_access" {
#   route_table_id         = "${aws_vpc.test2.main_route_table_id}"
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = "${aws_internet_gateway.gw1.id}"
# }

locals {
  # The value of availability zone is derived from region plus letters a-f
  # Useful for building out the VPC in regions. Region need to have atleast 
  # 4 regions. o ther than us-east-1, use ap-northeast-2
  az_a = "${var.aws_region}a"
  az_b = "${var.aws_region}b"
  az_c = "${var.aws_region}c"
  az_d = "${var.aws_region}d"
  az_f = "${var.aws_region}f"
}

# Create 5 subnets to launch our instances into
# The first two are private, the remaining three public
resource "aws_subnet" "Private_1A" {
  vpc_id = data.aws_vpc.selected.id
  cidr_block              = "192.168.10.192/27"
  availability_zone = "${local.az_a}"
  map_public_ip_on_launch = false
  tags                    = {
     "Name" = "Private_1A" 
     }
}

resource "aws_subnet" "Private_1D" {
  vpc_id = data.aws_vpc.selected.id
  cidr_block              = "192.168.10.224/27"
  map_public_ip_on_launch = false
  availability_zone = "${local.az_d}"  
  tags                    = {
     "Name" = "Private_1D" 
     }
}
resource "aws_subnet" "Public_1A" {
  vpc_id = data.aws_vpc.selected.id
  cidr_block              = "192.168.10.64/27"
  map_public_ip_on_launch = true
  availability_zone = "${local.az_a}"
  tags                    = {
     "Name" = "Public_1A" 
     }
}
resource "aws_subnet" "Public_1D" {
  vpc_id = data.aws_vpc.selected.id
  cidr_block              = "192.168.10.128/27"
  map_public_ip_on_launch = true
  availability_zone = "${local.az_a}"
  tags                    = {
     "Name" = "Public_1D" 
     }
}

## If your region does not have an 'F' AZ -  comment this out entirely 
## and update lamdba_handler.tf to use 'Public_1A' or 'Public_1D' for AZ 
resource "aws_subnet" "Public_1F" {
  vpc_id = data.aws_vpc.selected.id
  cidr_block              = "192.168.11.128/27"
  map_public_ip_on_launch = true
  availability_zone = "${local.az_f}"
  tags                    = {
     "Name" = "Public_1F" 
     }
}

## You will not be able to ssh into your instance if you
## do not include your PC/laptop public IP in allowed CIDRs
data "aws_ssm_parameter" "vpc_test2_default_sg_cidrs" {
      name = "vpc_test2_default_sg_cidrs"
}

## Warning: this will alter a security group called 'default' if it exists
resource "aws_security_group" "default" {
  name        = "default"
  description = "default VPC security group"
  vpc_id      = data.aws_vpc.selected.id

  # Access from anywhere to port 23 and up - ssh blocked from everywhere by default
  # Comment this out if you do not need any open ports above port 22
  ingress {
    description = "exclude ports under 23"
    from_port   = 23
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All access from within the VPC and select public ranges
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = split(",", data.aws_ssm_parameter.vpc_test2_default_sg_cidrs.value)
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# We instantiate 1 on-demand in AZ Public 1D.  Spot AZ is defined in variables.tf ('aws_az')
resource "aws_instance" "tf-instance" {
  ami   = "${var.ami_id}"
  associate_public_ip_address = true
  instance_type = "${var.instance_type}"
  subnet_id = "${aws_subnet.Public_1D.id}"
  key_name   = "${var.key_name}"
  vpc_security_group_ids = [
    "${aws_security_group.default.id}"
    ]
  connection {
  	user = "ec2-user"
  }
  tags     = {
    "Name" = "TLC" 
     }
  lifecycle {
    ignore_changes = [
      ## ignore for the on-demand instance, if already instantiated
      ## these options are primarily for the spot instance gh runner(s)
      ami,
      instance_type,
      key_name,
      tags
    ]
  } 
}

# Create a custom EventBridge event bus
resource "aws_cloudwatch_event_bus" "custom_bus" {
  name = "custom-event-bus" # Required: The name of your custom event bus
}

# Create a repository secret for OIDC - optional, ec2 instance profile suffices.
# The webhook should call OIDC and get the ACCOUNT_ID, as needed.
locals { repo = basename(var.repo_name) }
resource "github_actions_secret" "account_id" {
  repository      = "${local.repo}"
  secret_name     = "ACCOUNT_ID"
  plaintext_value = ""  # "${data.aws_caller_identity.current.account_id}" to store in GH
}

data "github_actions_registration_token" "spot_runner" {
  repository = "${local.repo}"
}

output "registration_token" {
  value     = data.github_actions_registration_token.spot_runner.token
  sensitive = true # Mark as sensitive to prevent logging the token
}

output "token_expiration" {
  value = data.github_actions_registration_token.spot_runner.expires_at
}
# Output the ARN of the created event bus
output "event_bus_arn" {
  value = aws_cloudwatch_event_bus.custom_bus.arn
}
