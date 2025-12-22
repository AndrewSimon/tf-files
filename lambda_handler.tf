# Public 1F from AZ us-east-1f has lower spot prices.
data "aws_vpc" "main" {
  tags = {
    Name = var.vpc_name
  }
}
#  If your region does not have an 'F' AZ, change tags to "Public 1A" or "Public 1D"
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

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

EC2_CLIENT = boto3.client('ec2', region_name='${var.aws_region}')
# Right now, this deploys to whatever your 'default' vpc is set to in your account, 
# not the one tf-files just created.  We default to Az 'f' in hopes of lower spot costs. 
#
AVAILABILITY_ZONE = '${var.aws_az}'
AMI_ID = '${var.ami_id}' # Technology Leadership LLC's OL96 AMI 
INSTANCE_TYPE = '${var.instance_type}'
SUBNET_ID = '${local.public_subnet_ids_list[0]}'
KEY_NAME = '${var.key_name}'
TAG_KEY = 'runner'
TAG_VALUE = 'true' # or any value, e.g., 'active'
#WEBHOOK_SECRET = '${data.aws_ssm_parameter.gh_webhook_secret.value}'
GH_RUNNER_TOKEN = '${data.github_actions_registration_token.spot_runner.token}'

USERDATA = """#!/bin/bash
export TOKEN=$(curl -X PUT "169.254.169.254" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export RUNNER_TOKEN=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v 169.254.169.254/latest/meta-data/tags/instance/GH_REG_TOKEN 2>/dev/null)
sudo -u gh-runner bash -c "cd /home/gh-runner && ./config.sh --url https://github.com/AndrewSimon/tf-files --token $RUNNER_TOKEN --unattended --replace --name tlc-spot-runner"
nohup sudo -u gh-runner bash -c 'cd /home/gh-runner && ./run.sh' &
"""

def lambda_handler(event, context):
    """
    Checks for a running spot instance with a specific tag and launches one if none exists.
    """
    
    # 1. Check for existing running instances with the tag 'runner'
    existing_instances = EC2_CLIENT.describe_instances(
        Filters=[
            {'Name': 'tag:' + TAG_KEY, 'Values': [TAG_VALUE]},
            {'Name': 'instance-state-name', 'Values': ['pending', 'running']},
            {'Name': 'instance-lifecycle', 'Values': ['spot']}
        ]
    )

    instance_count = sum(len(res['Instances']) for res in existing_instances['Reservations'])

    if instance_count > 0:
        logger.info(f"Found {instance_count} existing spot instance(s) with tag '{TAG_KEY}'. No new instance launched.")
        return {
            'statusCode': 200,
            'body': f"Instance already running. Count: {instance_count}"
        }

    # 2. If no matching instance is running, launch a new one-time spot instance
    logger.info(f"No existing instance found. Launching a new '{INSTANCE_TYPE}' spot instance in '{AVAILABILITY_ZONE}'...")

    try:
        # Use RunInstances API with SpotOptions for modern spot requests. The legacy request_spot_instances is discouraged.
        response = EC2_CLIENT.run_instances(
            ImageId=AMI_ID,
            InstanceType=INSTANCE_TYPE,
            KeyName=KEY_NAME,
            SubnetId=SUBNET_ID,
            MaxCount=1,
            MinCount=1,
            Placement={
                'AvailabilityZone': AVAILABILITY_ZONE
            },
            UserData=USERDATA,
            TagSpecifications=[
                {
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': TAG_KEY, 'Value': TAG_VALUE},
                        {'Key': 'GH_REG_TOKEN', 'Value': GH_RUNNER_TOKEN},
                        {'Key': 'Name', 'Value': 'tlc-runner-spot-instance'}
                    ]
                },
                {
                    'ResourceType': 'volume',
                    'Tags': [
                        {'Key': TAG_KEY, 'Value': TAG_VALUE},
                        {'Key': 'Name', 'Value': 'tlc-runner-spot-volume'}
                    ]
                }
            ],
            MetadataOptions={
                'HttpTokens': 'required', # Optional: enforces IMDSv2
                'InstanceMetadataTags': 'enabled' # This enables tag access
            },
            # Request as a Spot Instance
            InstanceMarketOptions={
                'MarketType': 'spot',
                'SpotOptions': {
                    'SpotInstanceType': 'one-time',
                }
            }
        )
        instance_id = response['Instances'][0]['InstanceId']
        logger.info(f"Successfully launched new instance: {instance_id}")
        print(f"Instance {instance_id} is launched, cannot for status check ok or gh will timeout!")
        #waiter = EC2_CLIENT.get_waiter('instance_status_ok')
        #waiter.wait(InstanceIds=[instance_id])
        return {
            'statusCode': 200,
            'body': f"Instance {instance_id} is now launched!"
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


resource "aws_kms_key" "lambda_key" {
#  key_id = data.aws_ssm_parameter.lambda_kms_key_id.value
     policy = jsonencode({
       Version = "2012-10-17",
       Statement = [
         {
           Sid    = "Enable IAM policies",
           Effect = "Allow",
           Principal = {
             AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          },
           Action   = "kms:*",
           Resource = "*"
         },
       ]
     })
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

# Grant permission for the public URL to invoke the Lambda
#resource "aws_lambda_permission" "allow_public_invoke" {
#  statement_id  = "AllowPublicInvoke"
#  action        = "lambda:InvokeFunction"
#  function_name = aws_lambda_function.spot_runner.function_name
#  principal     = "*"
  # SourceArn/SourceAccount constraints are not applicable for public function URLs
#}

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
