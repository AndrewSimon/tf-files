# tf-files 

This is a terraform plan that:

1) Creates a new VPC
2) In that VPC: Creates two 2 tier subnets (one public, one private) for high availability
3) In that VPC: Creates an Internet Gateway
4) In that VPC: Creates Routing tables
5) Creates a key pair - commented as you'll use an existing key pair
6) Gets the SG CIDR blocks (list) from SSM
7) Creates a Security Group
8) Instantiate one server in one of the Public subnets
9) As part of instantiation, assign the sg created earlier and adds a public IP

## Create an SSM parameter via console UI (not coded here)
1. Enter AWS Systems Manager
2. Click Parameter Store
3. Click Create Parameter
4. Create a StringList type parameter with name used in your terraform
5. Enter the CIDR list into values field, no spaces or quotes. E.g 123.123.123.123/32,224.242.224.0/24,10.0.0.0/16

## tf-files Install Instructions

1. Change directory to the location you want your terraform plan to be, usually your home directory

2. Using the git command-line:

```
git clone https://github.com/AndrewSimon/tf-files
```

## Terraform Install Instructions:

```
https://www.terraform.io/intro/getting-started/install.html
```

### tf-files Configuration Instructions:

cd tf-files

variables.tf:  
1) modify key_name to an SSH key pair name you already created in AWS and it's public key file path you saved locally<BR/>
2) Update the ami_id default value to an existing AMI in your region (the one used in the example has been unpublished)

config.tf:  
1) Change the name of the bucket used for s3 backend  and update your region, if not <b>us-east-1</b>.

main.tf:
1) Nothing needs to change.  To change 'Test2' to another VPC name, replace all occurrences of the string "Test2" with a VPC name you like


### Running command-line Terraform commands to test, execute and destroy tf-files

cd tf-files

To test, run: terraform plan

To execute, run: terraform apply

To cleanup, run: terraform destroy

## Maintainers

AndrewSimon
Written: 2016
Modified: 12/2/2025 

### Copyright and license

Copyright 2016, Andrew Simon (asimon@asimon.net)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License in the LICENSE file, or at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
