# tf-files 

This is a terraform plan that:

1.  Creates a new VPC
2.  In that VPC: Creates 5 subnets in two tiers (three public, two private) for high availability
3.  In that VPC: Creates an Internet Gateway
4.  In that VPC: Creates Routing table and route to igw
5.  Imports a key pair (just needs public key), uses an existing known working key pair
6.  Gets SG CIDR blocks (list), GH token and other secrets from SSM parameter store
7.  Creates a Security Group
8.  Instantiates one on-demand server in one of the Public subnets
9.  As part of instantiation, assign the sg created earlier and adds a public IP
10. Creates a github.com webhook for the tf-files with push trigger
11. Creates an AWS lambda function and lambda url for the webhook to contact
12. Lambda uses boto3 to instantiate a spot instance to create a github self-hosted runner
13. Contains a github action to queue a job that runs when the runner is available
14. The github action runs a simple aws api via boto3 to show the runner works
15. Creates a lot of IAM policy documents and roles for steps 1-14 above to work

## Prerequisites
The packages and setup required to be installed before starting are:

1. chrome (or similar) browser to access the AWS Console
2. git client
3. awscliv2
4. terraform
5. An SSM parameter store value used for the AWS Security Group CIDR list
6. An s3 bucket for the terraform 'backend' to use to store terraform state 

## Install AWSCLI Version 2 on your local device
1. On linux: `sudo dnf install awscli` or  On Windows: `choco install awscli`
2. First time only, run and complete 'aws configure' - terraform can find your AWS credential file

## Terraform Install Instructions:

```
https://www.terraform.io/intro/getting-started/install.html
```
  
## Create an s3 bucket for the back-end (not coded here)
`aws s3 mb s3://<name-of-the-bucket-to-store-state-files>`  --> without angle brackets and with a unique name
<P>The name of the bucket must be the same as the one you configure in config.tf

## Create an SSM parameter (not coded here)
SSM parameter store can be used for sensitive data like <i>F/W (SG) IP allow ranges</i> that should not go into a public repository. Creating the store via terraform here would only push the secrets to another platform, like local environment variables or a tfvars file.

1. Enter AWS Systems Manager
2. Click Parameter Store
3. Click Create Parameter
4. Create a StringList type parameter with name used in your terraform
5. Enter the CIDR list into values field, no spaces or quotes. E.g 123.123.123.123/32,224.242.224.0/24,10.0.0.0/16
6. Repeat for other secrets, as needed

## tf-files Install Instructions
1. Change directory to the location you want your terraform plan to be, usually your home directory
2. Using the git command-line, clone and checkout the 'workflow' branch, which is newest:

```
git clone -b workflow https://github.com/AndrewSimon/tf-files
```

### tf-files Configuration Instructions:

cd tf-files

variables.tf:  
1. Modify key_name to an SSH key pair name you already created in AWS and it's public key file path you saved locally
2. Update the ami_id default value to an existing AMI in your account - uses a TLC AMI

config.tf: Change the name of the bucket used for s3 backend and update your region, if not <b>us-east-1</b>.

main.tf: Nothing needs to change. Optionally, change 'test2' to another VPC name, replace all occurrences of the string "test2" with a VPC name you like

### Run command-line Terraform commands to test, execute and destroy
1. cd tf-files
2. First time only, run: terraform init
3. To test, run: terraform plan
4. To execute with automatic 'yes', run: terraform apply -auto-approve
5. To override AZ placement of runner to us-east-1a (for example), run: terraform apply -auto-approve -var="aws_az=us-east-1a" -var="aws_subnet_tag=Public_1A"
6. If no capacity for spot and/or want on-demand, run: terraform apply -auto-approve -var="spot_market=false"
7. To cleanup, run: terraform destroy

### Trouble-shooting
Most early problems will involve AWS credentials.  Ensure your user account can create resources in the console.  The `aws s3 mb` command will work as long as it is a <i>unique</i> bucket name and your account has the create bucket access policy.  Confirm in the console you can create and read an existing s3 bucket, if you cannot do so command-line.  Do the same type of access check via Console for the SSM parameter store, VPC component, and EC2 instance creation, as well.  Adjust user account roles and policies, as needed.

For terraform errors, make sure the variable name that stores the <i>value</i>, such as bucket name, AWS key pair name, the SSM parameter store name, and so on, is not mismatched between the variable names and value types defined in variables.tf versus the resource variable names and value types expected in main.tf.  An example of a mismatch in value type is when the value is a string when it should be a list.  The example of a resource name mismatch is when the name given to a value in variables.tf is <i>xy-z</i> but the resource expects the name to be <i>xy_z</i>.  

## Maintainers

AndrewSimon
Written: 2016
Modified: 12/2025 

### Copyright and license

Copyright 2016-2025, Andrew Simon (asimon@asimon.net)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License in the LICENSE file, or at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
