
resource "local_file" "lambda_handler" {
  filename = "lambda_handler.py"
  content  = <<-EOT

# This is a generated script by Terraform lambda_handler.tf

import boto3
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

EC2_CLIENT = boto3.client('ec2', region_name='us-east-1')
# AMI ID for the official Rocky Linux 9.x minimal image in us-east-1
# This ID might need periodic updates. The owner is the official AWS Marketplace account (679593333241)
# A known AMI ID for Rocky 9.5 (as of late 2024/early 2025) is ami-0aa1786a50c788578.
# For robustness, consider dynamically fetching the latest AMI via SSM Parameter Store or describe_images filter
# if the AMI ID in this code becomes outdated.
AMI_ID = '${var.ami_id}' # Technology Leadership LLC's OL96 AMI 
INSTANCE_TYPE = '${var.instance_type}'
AVAILABILITY_ZONE = '${var.aws_az}'
TAG_KEY = 'runner'
TAG_VALUE = 'true' # or any value, e.g., 'active'

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
            MaxCount=1,
            MinCount=1,
            Placement={
                'AvailabilityZone': AVAILABILITY_ZONE
            },
            TagSpecifications=[
                {
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': TAG_KEY, 'Value': TAG_VALUE},
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
        return {
            'statusCode': 200,
            'body': f"Launched new instance: {instance_id}"
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
          "ec2:DescribeInstances"
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

# AWS Lambda function resource
resource "aws_lambda_function" "spot_runner" {
  function_name    = "SpotRunner"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256 # This line is crucial
  handler          = "lambda_handler.lambda_handler" # Format: file_name.function_name
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_execution_role.arn

  # Optional: Define environment variables, memory size, etc.
  environment {
    variables = {
      GREETING = "Hello"
    }
  }
}

# Optional: Output the function name
output "lambda_function_name" {
  value = aws_lambda_function.spot_runner.function_name
}
