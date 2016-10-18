# tf-files 

This is a terraform plan that:

1) Creates a new VPC
2) In that VPC: Creates two 2 tier subnets (one public, one private) for high availability
3) In that VPC: Creates an Internet Gateway
4) In that VPC: Creates Routing tables
5) Creates a key pair - commented as you'll use an existing key pair
6) Creates a Security Group
7) Instantiate one server in one of the Public subnets
8) As part of instantiation, assign the sg created earlier and adds a public IP

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

auth.tf:  modify public_key_path and key_name to match your environment
main.tf:  modify key_name to an SSH key pair you already created in AWS
config.tf: modify your aws key and aws secret to match your AWS account


### Running command-line Terraform commands to test, execute and destroy tf-files

cd tf-files

To test, run: terraform plan
To execute, run: terraform apply
To cleanup, run: terraform destroy

## Maintainers

AndrewSimon

### Copyright and license

Copyright 2016, Andrew Simon (asimon@asimon.net)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License in the LICENSE file, or at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
