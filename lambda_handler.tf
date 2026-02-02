# Public 1F from AZ us-east-1f has lower spot prices.
data "aws_vpc" "main" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id] 
  }
  tags = {
    Name = var.aws_subnet_tag
  }
}

data "aws_ssm_parameter" "gh_webhook_secret" {
      name = "gh_webhook_secret"
      with_decryption = true
}

locals {
  # Convert the set of IDs to a list for easier indexing
  public_subnet_ids_list = tolist(data.aws_subnets.public.ids)
}

output "spot_public_subnet_id" {
  # Get the ID of the first subnet in the list
  value = local.public_subnet_ids_list[0]
}

resource "local_file" "lambda_handler" {
  filename = "lambda_handler.py"
  content  = <<-EOT

# This is a generated script by Terraform lambda_handler.tf

import boto3
import logging
import hmac
import hashlib
import json
import secrets
from hmac import compare_digest

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

EC2_CLIENT = boto3.client('ec2', region_name='${var.aws_region}')
# Right now, this deploys to whatever your 'default' vpc is set to in your account, 
# not the one tf-files just created.  We default to Az 'f' in hopes of lower spot costs. 
#
AWS_REGION = '${var.aws_region}'
AVAILABILITY_ZONE = '${var.aws_az}'
AMI_ID = '${var.ami_id}' # Technology Leadership's GHR AMI 
INSTANCE_TYPE = '${var.instance_type}'
SUBNET_ID = '${local.public_subnet_ids_list[0]}'
KEY_NAME = '${var.key_name}'
TAG_KEY = 'runner'
TAG_VALUE = 'true' # or any value, e.g., 'active' as we check for key
WEBHOOK_SECRET = '${data.aws_ssm_parameter.gh_webhook_secret.value}'
#GH_RUNNER_TOKEN = '${data.github_actions_registration_token.spot_runner.token}'
GH_PAT = '${data.aws_ssm_parameter.gh_pat.value}'
PROFILE_NAME = '${var.instance_profile}'
REPO_NAME = '${var.repo_name}'
VOL_SIZE = ${var.volume_size} #Integer
SPOT_MARKET = ${var.spot_market} #Boolean
MAX = ${var.max_instances} #Integer

MKT_OPT = "spot" if SPOT_MARKET else "on-demand"

USERDATA = f"""#!/bin/bash
#  runner hook to complete dynamically provisioned instance lifecycle

#### MUST BE IDMSV2! Below is IDMSV1
echo "TOKEN=\$(curl -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\")"  > /home/gh-runner/bin/complete_lifecycle.sh
echo "INSTANCE_ID=\$(curl -H \"X-aws-ec2-metadata-token: \$TOKEN\" 169.254.169.254/latest/meta-data/instance-id)" >> /home/gh-runner/bin/complete_lifecycle.sh
echo "AWS_REGION=\$(curl -s http://169.254.169.254/latest/meta-data/placement/region)" >> /home/gh-runner/bin/complete_lifecycle.sh
echo "/home/gh-runner/bin/aws ec2 terminate-instances --instance-ids \$INSTANCE_ID --region {AWS_REGION}" >> /home/gh-runner/bin/complete_lifecycle.sh
chmod +x /home/gh-runner/bin/complete_lifecycle.sh
# Comment out the below line to NOT terminate instance after running a job
export ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/home/gh-runner/bin/complete_lifecycle.sh

# Configure runner and connect to server
export DEFAULT_MAX=1
export RUNNER_TOKEN=$(curl -s -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: Bearer {GH_PAT}" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/{REPO_NAME}/actions/runners/registration-token| grep token|awk -F\\" '{{print $4}}')
sudo -u gh-runner bash -c "cd /home/gh-runner && ./config.sh remove --token $RUNNER_TOKEN"
sudo -u gh-runner bash -c "cd /home/gh-runner && ./config.sh --url https://github.com/{REPO_NAME} --token $RUNNER_TOKEN --unattended --replace --name tlc-{MKT_OPT}-runner-$DEFAULT_MAX"
nohup sudo -u gh-runner bash -c 'cd /home/gh-runner && ./run.sh' &
"""

def validate_signature(github_signature, payload_body, secret_token):
    """
    Validates the GitHub webhook signature.
    """
    if not github_signature.startswith("sha256="):
        return False
    expected_signature = github_signature.split("=")[1]
    # Calculate the HMAC-SHA256 hash of the payload body
    h = hmac.new(secret_token.encode('utf-8'), payload_body, hashlib.sha256)    
    calculated_signature = h.hexdigest()
    # Compare signatures using a timing-safe method
    return compare_digest(calculated_signature, expected_signature)


def lambda_handler(event, context):
    """
        Validates the GH webhook secret via it's signature before anything else
    """
    signature = event['headers'].get('x-hub-signature-256') or event['headers'].get('X-Hub-Signature-256')
    body = event['body']
    if event.get('isBase64Encoded'):
        import base64
        body = base64.b64decode(body)
    else:
        body = body.encode('utf-8')

    if not signature or not validate_signature(signature, body, WEBHOOK_SECRET):
        return {
            'gotSecret': WEBHOOK_SECRET,
            'statusCode': 401,
            'body': json.dumps('Invalid signature - if gotSecret matches SSM store value, SSM does not match what GH webhook sent.')
        }
        
    """
    Checks for a running spot or on-demand instance with a specific tag and launches one if none exists.
    """
    # Declare USERDATA global so we can reassign it's value within this function
    global USERDATA
    
    # Check for tag key 'runner' separately as missing tag keys report an
    # empty set, creating a false positive when used together with other filters
    existing_instances = EC2_CLIENT.describe_instances(
        Filters=[
            {'Name': 'tag:' + TAG_KEY, 'Values': [TAG_VALUE]},
        ]
    )
    instance_count = sum(len(res['Instances']) for res in existing_instances['Reservations'])

    # If we find any instances with tag key 'runner' we safely reassign count value based on state
    if instance_count > 0:
        logger.info(f"Found {instance_count} instance(s) with tag '{TAG_KEY}', checking instance state...")
        existing_instances = EC2_CLIENT.describe_instances(
          Filters=[
              {'Name': 'tag:' + TAG_KEY, 'Values': [TAG_VALUE]},
              {'Name': 'instance-state-name', 'Values': ['pending', 'running']},
#              Uncomment to check ONLY for spot instances - results in unlimited on-demand
#              {'Name': 'instance-lifecycle', 'Values': ['spot']} # specify on-demand for unlimited spot
          ]
        )
    instance_count = sum(len(res['Instances']) for res in existing_instances['Reservations'])
       
    if instance_count >= MAX:
        logger.info(f"Found {instance_count} existing instance(s) with tag '{TAG_KEY}'. No new instance launched.")
        return {
            'statusCode': 200,
            'body': f"Found {instance_count} instances running while {MAX} allowed, no new instances launched."
        }

    # Update USERDATA tags with marketplace option, max count and current existing count
    USERDATA = USERDATA.replace("$DEFAULT_MAX", str(instance_count))
    # If no matching instance is running, launch a new one-time spot instance
    logger.info(f"{instance_count} instances found. Launching a new '{INSTANCE_TYPE}' '{MKT_OPT}' instance in '{AVAILABILITY_ZONE}'...")

    params = {
      'ImageId': AMI_ID,
      'InstanceType': INSTANCE_TYPE,
      'KeyName': KEY_NAME,
      'SubnetId': SUBNET_ID,
      'MaxCount': 1,
      'MinCount': 1,
      'BlockDeviceMappings': [
      {
        'DeviceName': '/dev/sda1',
        'Ebs': {
            'DeleteOnTermination': True, # Explicitly ensures the EBS volume is deleted
            'VolumeSize': VOL_SIZE, # Size in GiB
            'VolumeType': 'gp3',
          },
        },
      ],
      'IamInstanceProfile': {
        'Name': PROFILE_NAME # Specify the profile name here
      },
      'Placement': {
          'AvailabilityZone': AVAILABILITY_ZONE
      },
      'UserData': USERDATA,
      'TagSpecifications' :[
          {
            'ResourceType': 'instance',
            'Tags': [
                {'Key': TAG_KEY, 'Value': TAG_VALUE},
 #                 {'Key': 'GH_REG_TOKEN', 'Value': GH_RUNNER_TOKEN},
                  {'Key': 'Name', 'Value': 'tlc-runner-' + MKT_OPT + '-instance-' + str(instance_count)}
              ]
          },
          {
              'ResourceType': 'volume',
              'Tags': [
                  {'Key': TAG_KEY, 'Value': TAG_VALUE},
                  {'Key': 'Name', 'Value': 'tlc-runner-' + MKT_OPT + '-instance-' + str(instance_count)}
              ]
          }
        ],
        'MetadataOptions': {
            'HttpTokens': 'required', # Optional: enforces IMDSv2
            'InstanceMetadataTags': 'enabled' # This enables tag access
        },   
    }
    
    if SPOT_MARKET:
      params['InstanceMarketOptions'] = {
          'MarketType': 'spot',
          'SpotOptions': {
              'SpotInstanceType': 'one-time',
          }
      }
    else:
      pass
      
    try:
        response = EC2_CLIENT.run_instances(**params)
        instance_id = response['Instances'][0]['InstanceId']
        logger.info(f"Successfully launched new {MKT_OPT} instance: {instance_id}")
        print(f"Instance {instance_id} is launched, cannot wait for status check ok or webhook will timeout!")
        #waiter = EC2_CLIENT.get_waiter('instance_status_ok')
        #waiter.wait(InstanceIds=[instance_id])
        return {
            'statusCode': 200,
            'body': f"Found {instance_count} instances running while {MAX} allowed, {MKT_OPT} instance {instance_id} is now launched!"
        }

    except Exception as e:
        logger.error(f"Error launching instance: {str(e)}")
        return {
            'statusCode': 500,
            'body': f"Error: {str(e)}"
        }

  EOT
  file_permission = "0755" # Optional: set appropriate file permissions
}

# Data source to create the deployment package (ZIP file)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_handler.py"
  output_path = "lambda_handler.zip"
  depends_on = [
    local_file.lambda_handler
  ]
}

# For access to Lambda
data "aws_iam_policy_document" "AWSLambdaTrustPolicy" {
  statement {
    actions    = ["sts:AssumeRole"]
    effect     = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# For access to KMS
resource "aws_iam_policy" "kms_decrypt_policy" {
  name        = "lambda_kms_decrypt_policy"
  description = "A policy that allows the Lambda function to decrypt with the AWS managed key"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey" # Optional: useful for verification/logging
        ]
        Resource = "*"
      }
    ]
  })
}

# For access to EC2 DescribeInstances
resource "aws_iam_policy" "ec2_describe_policy" {
  name        = "lambda_ec2_describe_policy"
  description = "A policy that allows the Lambda function to describe EC2 instances"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      }
    ]
  })
}

# For access to EC2 RunInstances
resource "aws_iam_policy" "ec2_run_policy" {
  name        = "lambda_ec2_run_policy"
  description = "A policy that allows the Lambda function to run EC2 instances"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role that the Lambda function will assume 
resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.AWSLambdaTrustPolicy.json
}

# IAM policy attachment for basic Lambda execution (logging to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy attachment for basic Lambda access to KMS
resource "aws_iam_role_policy_attachment" "lambda_kms" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.kms_decrypt_policy.arn
}

# IAM policy attachment for basic Lambda access to EC2
resource "aws_iam_role_policy_attachment" "lambda_ec2" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.ec2_run_policy.arn
}

# Attach the spot_policy from spot_instance_role to the lambda_execution_role
resource "aws_iam_role_policy_attachment" "lambda_spot" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.spot_policy.arn
  depends_on = [
    aws_iam_policy.spot_policy
  ]
}

# Register the webhook in GitHub
resource "github_repository_webhook" "tf_webhook" {
  repository = "tf-files"
  configuration {
    url          = aws_lambda_function_url.spot_lambda_url.function_url
    content_type = "json"
    insecure_ssl = false # Set to true if not using HTTPS (not recommended)
    # The secret should be stored securely in a secret manager and passed here
    secret       = data.aws_ssm_parameter.gh_webhook_secret.value
  }
  active = true
  events = ["push"] # Choose the events you need
}

# AWS Lambda function resource
resource "aws_lambda_function" "spot_runner" {
  function_name    = "SpotRunner"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256 # This line is crucial
  handler          = "lambda_handler.lambda_handler" # Format: file_name.function_name
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_execution_role.arn
  timeout          = 900

  # Optional: Define environment variables, memory size, etc.
  environment {
    variables = {
      GREETING = "Hello"
    }
  }
}

# The real security is SSL - this is safe as long as github's SSL
# private key AND the DNS source (port 53) you use are not compromised
resource "aws_lambda_function_url" "spot_lambda_url" {
  function_name      = aws_lambda_function.spot_runner.function_name
  invoke_mode        = "RESPONSE_STREAM"
  authorization_type = "NONE" # Restrict access with 'AWS_IAM'
  cors {
    # Origins that can access the function URL
    allow_origins = ["https://api.github.com", "https://github.com"]
    # HTTP methods that are allowed when calling the function URL
    allow_methods = ["POST"]
    # HTTP headers that origins can include in requests
    #allow_headers = ["content-type", "authorization"]
    allow_headers = []
    # Whether to allow cookies or other credentials (optional, default is false)
    allow_credentials = false
    # Maximum amount of time - set this to match webhook timeout
    max_age = 10
    }
}

# Optional: Output the function name
output "lambda_function_name" {
  value = aws_lambda_function.spot_runner.function_name
}
