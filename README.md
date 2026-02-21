# tf-files 

This is a terraform plan that:

1.  Creates a new VPC
2.  In that VPC: Creates 5 subnets in two tiers (three public, two private) for high availability
3.  In that VPC: Creates an Internet Gateway
4.  In that VPC: Creates Routing table and route to igw
5.  Imports a key pair (just needs public key), uses an existing known working key pair
6.  Gets SG CIDR blocks (list), GH token and other secrets from SSM parameter store
7.  Creates a Security Group
8.  Instantiates one on-demand server in one of the Public subnets. NOT a runner. Either import an existing, or create a new one.
9.  As part of instantiation, assign the sg created earlier and adds a public IP
10. Creates a github.com webhook for the tf-files with push trigger
11. Creates an AWS lambda function and lambda url for the webhook to contact
12. Lambda uses boto3 to instantiate a (default) spot or on-demand instance to register as github self-hosted runner
13. Contains a github action to queue a job that runs when the runner is available
14. The github action installs dependencies, prints runner's OS (currently: Linux-5.15.0-101.103.2.1.el9uek.x86_64-x86_64-with-glibc2.34) and hostname, which discloses region instance is in.
15. MOST IMPORTANTLY: Creates the ACTIONS_RUNNER_HOOK_JOB_COMPLETED lifecycle (termination) step via ec2 instance user-data
16. Creates a lot of IAM policy documents and roles for steps 1-15 above to work

The Github Actions workflow comments describe the dependency install and how to modify to disable the Dynamic Runner life-cycle until reverted.  Life-cycle dependency on the repo job does return some control of the life-cycle from the 'administrator' back to the 'developer' using that repo.  Administrators need move only one step out of github actions to the user-data defined in terraform to remove non-Administrators' ability to disable the life-cycle.

## Prerequisites
The packages and setup required to be installed before starting are:

1. Chrome (or similar) browser to access the AWS Console
2. git client
3. awscliv2
4. Terraform
5. SSM parameter store values for AWS Security Group CIDR list, GH Pat, GH Webhook secret
6. An s3 bucket for the terraform 'backend' to use to store terraform state
7. Subscription to the TLC Github Actions Runner AMI (alternate AMI's are unsupported).

## Subscribe to Technology Leadership Corporation's GHR2.33 AMI:
1. Copy-and-paste the link below into your browser, and navigate to:
https://aws.amazon.com/marketplace/pp/prodview-zsmcixdrlp2ti
2. Click 'View Purchase options
3. Fill out the form, selecting hourly or yearly, etc.
4. Click Subscribe button

Once subscribed, you can get the AMI ID you will need for variables.tf or -var"_ami_id=<ami-i>" override:
1. From aws console, navigate to EC2 Dashboard --> Launch Instances button (below the Resources list box)
2. In 'Application and OS Images (Amazon Machine Image)' list box, selec the 'Browse more AMI' option box
3. Click AWS Marketplace AMIs, then--> Click 'Search for an AMI', enter: *runner by tlc*, hit enter
4. One entry will be found, Oracle Linux 9 with Github Actions Runner by TLC.  Click 'Select' button to the right of it
5. In 'AMI from Catalog' tab that is open, look for Image ID. In Seoul Korea*, it is ami-0718b118e794b9856
6. Cancel out of launching.  These will come up anytime your 'redeliver' a previous hook, or make a new push commit.

**For maximum spot capacity availability, I must use South Korea**
It is 13 or 14 hours ahead of my TZ. They have (tf-files required minimum) 4 AZ and it is their 10PM to 6AM during my 9am to 5pm EST

## Git Client Install on your local device:
```
https://git-scm.com/book/en/v2/Getting-Started-Installing-Git
```
## Install AWSCLI Version 2 on your local device
1. On linux: `sudo dnf install awscli` or  On Windows: `choco install awscli`
2. First time only, run and complete 'aws configure' - terraform can find your AWS credential file

## Terraform Install Instructions:

```
https://www.terraform.io/intro/getting-started/install.html
```
  
## Create an s3 bucket for the back-end (not coded here)
`aws s3 mb s3://<name-of-the-bucket-to-store-state-files> --region <your-aws-region>`  --> without angle brackets and with a unique name and AWS region.  Repeat for each region you want to utilize.
<P>The name of the bucket must be the same as the one you configure in config.tf and/or initialized (see below).

## Create an SSM parameter (not coded here)
SSM parameter store can be used for sensitive data like <i>F/W (SG) IP allow ranges</i> that should not go into a public repository. Using Terraform to create the store would bump secrets management to a less desirable method (like local environment variables or a tfvars file) and make retrieval of those values from SSM parameter store optional. Repeat 1 -6 below in each AWS region you wish to utilize.

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
2. Update the ami_id default value to an existing AMI in your account - uses a TLC AMI specified in variables.tf
3. config.tf: Uncomment and change the name of the bucket used for s3 backend and uncomment your region, variables are not accepted here - OR -
4. We have config.tf commented backend values to more easily support multiple regions as terraform init DOES support variables. Just run *export TF_CLI_ARGS_init="-backend-config=bucket=$BUCKET_NAME -backend-config=region=$AWS_REGION"* where you have already exported $BUCKET_NAME (the name of the s3 backend bucket) and AWS_REGION, then run terraform steps below

main.tf: Nothing needs to change. Optionally, change 'test2' to another VPC name, replace all occurrences of the string "test2" with a VPC name you like

### Run command-line Terraform commands to test, execute and destroy
1. cd tf-files
2. First time only, run: terraform init (or terraform init --reconfigure if multi-region)
3. To test, run: terraform plan
4. First time only, stand up the VPC first, run: terraform apply -target aws_vpc.test2
5. To execute the rest of the plan with automatic 'yes', run: terraform apply -auto-approve
6. First time only, re-run number 5 above!  Everything is created already so it runs fast.  This re-run is necessary for lambda to pick up the subnet id of the spot runner.  Lambda will have the sunbet id on all subsequent runs.
7. First time only, permission the lambda function url manually.  See Trouble-shooting, return code 403 below for instructions.
8. To override AZ placement and ami_id of runner to ap-northeast-1d (for example), run: terraform apply -auto-approve  -var="ami_id=ami-0fea7406b1a381700" -var="aws_subnet_tag=Public_1D"
9. If override spot market and/or want on-demand, run: terraform apply -auto-approve -var="spot_market=False"9
10. To override (to 50Gb, for example) the default root filesystem, run: terraform apply -auto-approve -var="volume_size=50"  
11. To cleanup, run: terraform destroy

### Trouble-shooting
Most early problems will involve AWS credentials.  Ensure your user account can create resources in the console.  The `aws s3 mb` command will work as long as it is a <i>unique</i> bucket name and your account has the create bucket access policy.  Confirm in the console you can create and read an existing s3 bucket, if you cannot do so command-line.  Do the same type of access check via Console for the SSM parameter store, VPC component, and EC2 instance creation, as well.  Adjust user account roles and policies, as needed.

For terraform errors, make sure you run terraform init, first. Ensure the variable name that stores the <i>value</i>, such as bucket name, AWS key pair name, the SSM parameter store name, and so on, is not mismatched between the variable names and value types defined in variables.tf versus the resource variable names and value types expected in the other .tf files.  An example of a mismatch in value type is when the value is a string when it should be a list.  The example of a resource name mismatch is when the name given to a value in variables.tf is <i>xy-z</i> but the resource expects the name to be <i>xy_z</i>.  

NoSuchEntity: The role with name lambda_execution_role cannot be found.  Do not change anything, just re-run terraform apply again.

For webhook errors and return codes:

1. We couldn't deliver this payload: this usually means there is no capacity for your spot instances. But, wait a minute or two sometimes as the hook may have worked but AWS exceeded Github 10 second wait time to respond
2. Timeout: this usually means there is no capacity for your spot instances. But, wait a minute or two as sometimes the hook worked but AWS exceeded Github 10 second wait time to respond
3. Return code 200:  This means the webhook succeeded. Verify in the details that an instance was launched, otherwise it will give a count of already running instances. To increase the number of allowed runners to 10, for example, override with -var="max_instances=10"
4. Return code 403: Permission denied. To permission the lambda function url manually: Go to Amazon AWS console lambda --> lambda functions --> SpotRunner --> Configuration --> Function URL -->  Edit (the updated policy shows automatically, do not type anything!) --> (scroll to bottom) Save. That's it!  Terraform (bug) does not permission this and therefore won't replace it.  The change exists until you run terraform destroy.  Without it, the lambda function url does not have permission to invoke lambda on Github's behalf. 
5. Return code 500: Read the body of the error. If it is InvalidAMIID.NotFound.  Specify the correct AMI ID in variables.tf or use ami_id override option 
6. Return code 502: Internal server error. This is a permission issue with lambda_execution_role usually from multi-region use. Run 'terraform destroy -target=aws_iam_role.lambda_execution_role', then run terraform apply.
7. Return code 401 - Invalid Signature: The webhook-secret does not match between the repository commit-hook and SSM.  Fix it in either SSM or the GH Webhook for that repo.  As a forged SSL from outside github.com will have been completely blocked from connecting to the lambda url, thus could not have sent lambda a webhook secret, it *must* be someone inside gitub.com domain who stumbled upon your Amazon lambda url, even though there is a 1 in 1.5e+54 chance of that happening (the chance of picking the right atom in Avagrado's number is *only* 1 in 6e+23), and sent you the wrong secret or worse, is trying to 'hack' you.  It is *much* more likely, though, that someone who has access to the webhook's repo where you are seeing this has updated the webhook secret without telling you.  Alternately, they have access to SSM and changed it there without telling you.  The rarity of hitting your lambda url is why the web secret is completely unnecessary; but for 'best practices', I waste your valuable (more so than a web secret) electrons verifying the signature for you, anyway. 

## Maintainers

AndrewSimon (CEO/President of Technology Leadership, LLC)

Written: 2016

Modified: 1/2026 


### Copyright and license

Copyright 2016-2026, Andrew Simon (asimon@asimon.net)

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License. You may obtain a copy of the License in the LICENSE file, or at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
