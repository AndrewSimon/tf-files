## Terraform main
## The key word 'resource' creates resources if not already imported
## Trying to create a resource with an existing name fails
## Order is not important, but in this case:
## 1) Create VPC and VPC components
## 2) Get the SSM parameter store value for undisclosed resource values
## 3) Create a Security Group
## 4) Create a key pair - commented as we'll use existing key
## 5) Instantiate the server
## 6) As part of instantiation, assign the sg created earlier and add a public IP


# Create a VPC to launch our instances into
resource "aws_vpc" "test2" {
  cidr_block = "192.168.10.0/24"
  enable_dns_hostnames = "true"
  tags                    = {
     "Name" = "test2" 
     }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "gw1" {
   vpc_id = "${aws_vpc.test2.id}"
   tags   = {
       "Name" = "gw1"
   }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.test2.id
  # Grant the VPC internet access on its main route table
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw1.id}"
  }
  tags = {
    Name = "rt-test2"
  }
}

# Example single route entry = not needed as was added above
# Grant the VPC internet access on its main route table
# resource "aws_route" "internet_access" {
#   route_table_id         = "${aws_vpc.test2.main_route_table_id}"
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = "${aws_internet_gateway.gw1.id}"
# }

# Create 5 subnets to launch our instances into
# The first two are private, the remaining three public
resource "aws_subnet" "Private_1A" {
  vpc_id = "${aws_vpc.test2.id}"
  cidr_block              = "192.168.10.192/27"
  map_public_ip_on_launch = false
  tags                    = {
     "Name" = "Private 1A" 
     }
}
resource "aws_subnet" "Private_1D" {
  vpc_id = "${aws_vpc.test2.id}"
  cidr_block              = "192.168.10.224/27"
  map_public_ip_on_launch = false
  tags                    = {
     "Name" = "Private 1D" 
     }
}
resource "aws_subnet" "Public_1A" {
  vpc_id = "${aws_vpc.test2.id}"
  cidr_block              = "192.168.10.64/27"
  map_public_ip_on_launch = true
  tags                    = {
     "Name" = "Public 1A" 
     }
}
resource "aws_subnet" "Public_1D" {
  vpc_id = "${aws_vpc.test2.id}"
  cidr_block              = "192.168.10.128/27"
  map_public_ip_on_launch = true
  tags                    = {
     "Name" = "Public 1D" 
     }
}

resource "aws_subnet" "Public_1F" {
  vpc_id = "${aws_vpc.test2.id}"
  cidr_block              = "192.168.11.128/27"
  map_public_ip_on_launch = true
  tags                    = {
     "Name" = "Public 1F" 
     }
}

data "aws_ssm_parameter" "vpc_test2_default_sg_cidrs" {
      name = "vpc_test2_default_sg_cidrs"
}

## A new security group
resource "aws_security_group" "default" {
  name        = "default"
  description = "default VPC security group"
  vpc_id      = "${aws_vpc.test2.id}"

  # Access from anywhere to port 23 and up
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
      ## configurable ami is not used for termination protected instances
      ami
    ]
  } 
}