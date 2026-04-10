## Terraform main
## The key word 'resource' creates resources if not already imported
## Trying to create a resource with an existing name fails
## Order is not important, but in this case:
## 1) Create VPC and VPC components - creates Public_1F if region AZ count > 5
## 2) Get the SSM parameter store value for undisclosed resource values
## 3) Create a Security Group
## 4) Create a key pair - commented as we'll use existing key
## 5) Instantiate one generic on-demand server (i.e. not the lambda created ephemeral spot runner)
## 6) As part of instantiation, assign the sg created earlier and add a public IP
## 7) Create Github and EventBridge (not used here) actions

data "aws_region" "current" {}

data "aws_availability_zones" "azs" {}

# Existing implies the vpc_name exists
data "aws_vpcs" "existing" {
  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}"]
  }
}

# We also use the webhook secret for the rancher admin password, when installed
data "aws_ssm_parameter" "gh_webhook_secret" {
      name = "gh_webhook_secret"
      with_decryption = true
}

# Datadog integration
data "aws_ssm_parameter" "dd_app_key" {
      name = "dd_app_key"
      with_decryption = true
}
data "aws_ssm_parameter" "dd_api_key" {
      name = "dd_api_key"
      with_decryption = true
}

# Apply this first! terraform apply -target aws_vpc.test2
resource "aws_vpc" "test2" {
  cidr_block = "192.168.10.0/24"
  enable_dns_hostnames = "true"
  tags                    = {
     "Name" = var.vpc_name 
     }
}

locals {
# If test2 vpc, TLC instance exists set bool 1 > 0 (true)
  vpc_exists      = length(data.aws_vpcs.existing.ids) > 0
#  instance_exists = length(data.aws_instances.existing.ids) > 0
# If bool true get vpc id, if false get from new vpc source
  #vpc_id = local.vpc_exists ? data.aws_vpcs.existing.ids[0] : one(aws_vpc.test2[*].id)
  vpc_id = try(data.aws_vpcs.existing.ids[0], null) 
  region_name    = data.aws_region.current.region
  vpc_count      = length(data.aws_vpcs.existing.ids)
#  instance_count = length(data.aws_instances.existing.ids)
  az_count  = length(data.aws_availability_zones.azs.names)
  az_a = "${local.region_name}a"
  az_b = "${local.region_name}b"
  az_c = "${local.region_name}c"
  az_d = "${local.region_name}d"
  az_f = "${local.region_name}f"
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "gw1" {
   vpc_id = local.vpc_id
   tags   = {
       "Name" = "gw1"
   }
}

resource "aws_route_table" "public_route_table" {
  count = local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  
  vpc_id = local.vpc_id
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


# Create 5 subnets to launch our instances into
# The first two are private, the remaining three public
resource "aws_subnet" "Private_1A" {
  count = local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  vpc_id = local.vpc_id
  cidr_block              = "192.168.10.192/27"
  availability_zone = "${local.az_a}"
  map_public_ip_on_launch = false
  tags                    = {
     "Name" = "Private_1A" 
     }
}

resource "aws_subnet" "Private_1D" {
  count = local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  vpc_id = local.vpc_id
  cidr_block              = "192.168.10.224/27"
  map_public_ip_on_launch = false
  availability_zone = "${local.az_d}"  
  tags                    = {
     "Name" = "Private_1D" 
     }
}
resource "aws_subnet" "Public_1A" {
  count = local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  vpc_id = local.vpc_id
  cidr_block              = "192.168.10.64/27"
  map_public_ip_on_launch = true
  availability_zone = "${local.az_a}"
  tags                    = {
     "Name" = "Public_1A" 
     }
}
resource "aws_subnet" "Public_1D" {
  count = local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  vpc_id = local.vpc_id
  cidr_block              = "192.168.10.128/27"
  map_public_ip_on_launch = true
  availability_zone = "${local.az_d}"
  tags                    = {
     "Name" = "Public_1D" 
     }
  depends_on = [
    local.vpc_id
  ]
}

## If your region does not have an 'F' AZ -  comment this out entirely 
## and update lamdba_handler.tf to use 'Public_1A' or 'Public_1D' for AZ 
resource "aws_subnet" "Public_1F" {
  count = local.az_count > 5 ? 1 : 0  # Do not create if region doesn't have > 5 AZ
  vpc_id = local.vpc_id
  cidr_block              = "192.168.11.128/27"
  map_public_ip_on_launch = true
  availability_zone = "${local.az_f}"
  tags                    = {
     "Name" = "Public_1F" 
     }
}

# Associate public subnets to rt-${vpc_name} to enable public access through igw
resource "aws_route_table_association" "Public_1A" {
  count = local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  subnet_id      = aws_subnet.Public_1A[0].id
  route_table_id = aws_route_table.public_route_table[0].id
}
resource "aws_route_table_association" "Public_1D" {
  count = local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  subnet_id      = aws_subnet.Public_1D[0].id
  route_table_id = aws_route_table.public_route_table[0].id
}
resource "aws_route_table_association" "Public_1F" {
  count = local.az_count > 5 && local.vpc_id != null && local.vpc_id != "" ? 1 : 0
  subnet_id      = aws_subnet.Public_1F[0].id
  route_table_id = aws_route_table.public_route_table[0].id   
}

## You will not be able to ssh into your instance if you
## do not include your PC/laptop public IP in allowed CIDRs
data "aws_ssm_parameter" "vpc_test2_default_sg_cidrs" {
      name = "vpc_test2_default_sg_cidrs"
}

## Warning: this this is the 'default' sg for our gh runners
resource "aws_security_group" "default" {
  name        = "ghrunner"
  description = "GitHub Runner VPC security group"
  vpc_id      = local.vpc_id
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
  lifecycle {
    ignore_changes = [
    ## Ignore if already terraform import the SG but name is different
      name,
      description
    ]
  }
}

# We instantiate 1 on-demand in AZ Public 1D.
resource "aws_instance" "tf-instance" {
#  count = local.instance_count == 0 ? 1 : 0
  ami   = "${var.ami_id}"
  associate_public_ip_address = true
  instance_type = "${var.instance_type}"
  subnet_id = "${aws_subnet.Public_1D[0].id}"
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
      ## ignore for the static on-demand instance, if already instantiated
      ## these options are primarily for ephemeral or non-existent instances
      ami,
      region,
      availability_zone,
      associate_public_ip_address,
      subnet_id,
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
  plaintext_value = ""  # "${data.aws_caller_identity.current.account_id}" will store in GH
}

# Create a repository secret for Rancher (when using a workflow that installs it
resource "github_actions_secret" "webhook_secret" {
  repository      = "${local.repo}"
  secret_name     = "WEBHOOK_SECRET_TOKEN"
  plaintext_value = "${data.aws_ssm_parameter.gh_webhook_secret.value}"
}

data "github_actions_registration_token" "spot_runner" {
  repository = "${local.repo}"
}

output "spot_subnet" {
  value = coalesce(join(",", local.subnet_list), aws_subnet.Public_1D[0].id, "PLEASE SET A NEW OR DIFFERENT var.spot_subnet_tag VALUE BY OVERRIDE TO GET A VALID SPOT SUBNET")
}
output "other_values" {
  value = "${aws_subnet.Public_1D[0].id}, ${var.aws_subnet_tag}, ${var.volume_size}, ${var.spot_market}"
}

