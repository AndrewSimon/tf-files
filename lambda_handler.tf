   # Public 1F from AZ us-east-1f has lower spot prices.
data "aws_vpc" "main" {
  tags = {
    Name = var.vpc_name
  }
  depends_on = [
    local.vpc_id
  ]
}

#Used by boto3 once there is a public IP
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id] 
  }
  tags = {
    Name = var.aws_subnet_tag
  }
  depends_on = [
    local.vpc_id
  ]
}

data "aws_subnet" "public_details" {
  for_each = toset(data.aws_subnets.public.ids)
  id       = each.value
}

# In hopes of lowest spot price, use last subnet in VPC, which is public by tf plan
locals {
  subnet_list = [for s in data.aws_subnet.public_details : s.id]
  spot_subnet = coalesce(join(",", local.subnet_list), aws_subnet.Public_1D[0].id, "PLEASE SET A NEW OR DIFFERENT var.spot_subnet_tag VALUE BY OVERRIDE TO GET A VALID SPOT SUBNET")
  # Build an ssm parameter store map of path defined in data resource, using zmap. Thanks AI!
  ssm_map = zipmap(
    data.aws_ssm_parameters_by_path.dd_api_key.names,
    data.aws_ssm_parameters_by_path.dd_api_key.values
  )
  # Fetch value if key found, else use 'dummy-value'. Don't create a real aws parameter store using fake values. 
  dd_apikey = lookup(local.ssm_map, "dd_api_key", "dummy-value")
  depends_on = [
    local.vpc_id,
    data.aws_ssm_parameters_by_path.dd_api_key
  ]
}

resource "local_file" "lambda_handler" {
  filename = "lambda_handler.py"
  content  = <<-EOT

# This is a generated script by Terraform lambda_handler.tf

import boto3
import sys
import time
import logging
import urllib3
import hmac
import hashlib
import json
import secrets
from hmac import compare_digest

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Configure boto3 client and ec2 user-data variables
EC2_CLIENT = boto3.client('ec2', region_name='${local.region_name}')
AWS_REGION = '${local.region_name}'
AMI_ID = '${var.ami_id}' # Technology Leadership's GHR AMI 
INSTANCE_TYPE = '${var.instance_type}'
SUBNET_ID = '${local.spot_subnet}'
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
VOLUME_TYPE = 'standard' #ie magnetic, it is cheapest.  Hard-code for gp2 or gp3 for SSD
DD_API_KEY = '${local.dd_apikey}' #If in SSM, will use value, otherwise defaults to 'dummy-value'
DD_SITE = '${var.dd_site}'
DD_TAGS = 'env:prod'

MKT_OPT = "spot" if SPOT_MARKET else "on-demand"
# Configure api.github.com http headers
http = urllib3.PoolManager()
gh_headers = {
    "Authorization": f"Bearer {GH_PAT}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "urllib3-script"
}
USERDATA = f"""#!/bin/bash
# Generate life-cycle script now to ensure it's created
cat <<'EOF' > /home/gh-runner/bin/complete_lifecycle.sh
trap 'exit 0' TERM
export QUEUED=$(curl -s -L   -H "Accept: application/vnd.github+json"   -H "Authorization: Bearer {GH_PAT}" -H "X-GitHub-Api-Version: 2022-11-28" "https://api.github.com/repos/AndrewSimon/tf-files/actions/runs?sort=created&direction=desc&per_page=25"|grep  -E '"id": [0-9]{{10}}'| sort -r -u| awk '{{print $2}}'|sed -e  's/,//g' |while read x
do
curl -s -L -H "Accept: application/vnd.github+json" -H "Authorization: Bearer {GH_PAT}" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/AndrewSimon/tf-files/actions/runs/$x/jobs
done | grep -e queued -e running |wc -l)
export CNT=$(/home/gh-runner/aws/dist/aws ec2 describe-instance-status --instance-ids $(/home/gh-runner/aws/dist/aws ec2 describe-instances --filters "Name=tag:runner,Values=*" --query 'Reservations[].Instances[].InstanceId' --output text) --filters Name=instance-state-name,Values=running,pending --query "length(InstanceStatuses[?InstanceStatus.Status!='ok' || SystemStatus.Status!='ok'])")

if (( $CNT > $QUEUED )) || (( $QUEUED == 0 )) || (( $CNT >= 1 )) ; then
    echo "Server count $CNT is greater than jobs on the queue $QUEUED or QUEUED = 0 or CNT >= 1, shutting down now"
    TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" 169.254.169.254/latest/meta-data/instance-id)
    AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" 169.254.169.254/latest/meta-data/placement/region)
    /home/gh-runner/aws/dist/aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $AWS_REGION
    exit 0
else
  echo "Keeping runners ($CNT) for jobs queued ($QUEUED). Not ending life-cycle, will let next job do it."
fi
EOF

# Comment out the below line to NOT terminate instance after running a job
echo ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/home/gh-runner/bin/complete_lifecycle.sh >> /etc/environment
chmod +x /home/gh-runner/bin/complete_lifecycle.sh
chmod +x /var/lib/cloud/instance/user-data.txt

# Set up Datadog if DD_SITE is not "" - remove schema first
export SITE="$(echo {DD_SITE}|cut -d '/' -f3)"
if [ "$SITE" != "" ]; then
DD_API_KEY="{DD_API_KEY}" DD_SITE="{DD_SITE}" bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"
echo "site: $SITE" >> /etc/datadog-agent/datadog.yaml
firewall-cmd --permanent --add-port=5001/tcp
systemctl restart datadog-agent 
fi
# List workflow runs for a repo
RESPONSE=$(curl -s -H "Authorization: token {GH_PAT}" -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/{REPO_NAME}/actions/runs")

# Use awk to parse the json and count runs
# It looks for "status" key and counts if it is "queued"
PENDING_COUNT=$(echo "$RESPONSE" | awk -F'[,:"]' '
    /"status":/ {{
        if ($5 == "queued") {{
            count++
        }}
    }}
    END {{ print count+0 }}
')
echo "Number of pending jobs: $PENDING_COUNT"
if (( $PENDING_COUNT == 0 )) ; then
  echo "No jobs pending, this runner is not needed, terminating in 5 seconds!"
  sleep 5
  shutdown -h now
fi
# Configure runner and connect to server
export DEFAULT_MAX=1
TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
export SUFFIX=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" 169.254.169.254/latest/meta-data/local-ipv4|awk -F. '{{print $4}}')
export RUNNER_TOKEN=$(curl -s -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: Bearer {GH_PAT}" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/repos/{REPO_NAME}/actions/runners/registration-token| grep token|awk -F\\" '{{print $4}}')
sudo -u gh-runner bash -c "cd /home/gh-runner && ./config.sh remove --token $RUNNER_TOKEN"
sudo -u gh-runner bash -c "cd /home/gh-runner && ./config.sh --url https://github.com/{REPO_NAME} --token $RUNNER_TOKEN --unattended --replace --name tlc-{MKT_OPT}-runner-$SUFFIX"
nohup sudo -u gh-runner bash -c 'cd /home/gh-runner && ./run.sh' &
"""

def validate_signature(github_signature, payload_body, secret_token):
    """
    Validates the GitHub webhook signature.
    """
    if not github_signature.startswith("sha256="):
        return False
    expected_signature = github_signature.split("=")[1]

    # print("GHWHS:" + secret_token) 
    # Calculate the HMAC-SHA256 hash of the payload body
    h = hmac.new(secret_token.encode('utf-8'), payload_body, hashlib.sha256)    
    calculated_signature = h.hexdigest()
    print("expected:" + expected_signature)
    print("calculated:" + calculated_signature)    
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
        headers = event.get('headers', {})
        
    logger.info(f"Headers: {json.dumps(headers)}")
    
    if not signature or not validate_signature(signature, body, WEBHOOK_SECRET):
        return {
            'ssmSecret': WEBHOOK_SECRET,
            'gotSignature': signature,
            'gotBody': body,
            ']gotSecret': secret,
            'statusCode': 401,
            'body': json.dumps('Invalid signature - if gotSecret matches SSM store value, SSM does not match what GH webhook sent.')
        }

    headers = event.get('headers', {})
    logger.info(f"Headers: {json.dumps(headers)}")
         
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
            'body': f"Found {instance_count} instances running while {MAX} allowed, no new instances launched.\nNo worries! The last runner keeps running until all queued jobs are completed."
        }

    # Update USERDATA tags with marketplace option, max count and current existing count
    USERDATA = USERDATA.replace("$DEFAULT_MAX", str(instance_count))
    # If no matching instance is running, launch a new one-time spot instance
    logger.info(f"{instance_count} instances found. Launching a new '{INSTANCE_TYPE}' '{MKT_OPT}' instance in '{SUBNET_ID}'...")

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
            'VolumeType': VOLUME_TYPE,
          },
        },
      ],
      'IamInstanceProfile': {
        'Name': PROFILE_NAME # Specify the profile name here
      },
      'InstanceInitiatedShutdownBehavior': 'terminate',
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
        print(f"The SHA256 signatures match, instance {instance_id} is launched, 10 second GH webhook timeout is to short to wait for EC2 status check!")
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

resource "aws_iam_role_policy_attachment" "lambda_kms_attach" {
  role       = "lambda_execution_role" # Ensure this matches your exact role name
  policy_arn = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
  depends_on = [
    aws_iam_role.lambda_execution_role
  ]  
}

# IAM policy attachment for basic Lambda execution (logging to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  depends_on = [
    aws_iam_role.lambda_execution_role
  ]
}

# IAM policy attachment for basic Lambda access to EC2
resource "aws_iam_role_policy_attachment" "lambda_ec2" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.ec2_run_policy.arn
  depends_on = [
    aws_iam_role.lambda_execution_role
  ]
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
  depends_on = [
    aws_iam_role.lambda_execution_role
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
  timeout          = 900

  # Optional: Define environment variables, memory size, etc.
  environment {
    variables = {
      GREETING = "Hello"
    }
  }
  depends_on = [
    aws_iam_role.lambda_execution_role
  ]
}

# The real security is SSL - this is safe as long as github's SSL
# private key AND the DNS source (port 53) you use are not compromised
resource "aws_lambda_function_url" "spot_lambda_url" {
  function_name      = aws_lambda_function.spot_runner.function_name
  invoke_mode        = "RESPONSE_STREAM"
  authorization_type = "NONE" # Restrict access with 'AWS_IAM'
  region = "${local.region_name}"
  cors {
    # Origins that can access the function URL
    allow_origins = ["https://api.github.com", "https://github.com"]
    # HTTP methods that are allowed when calling the function URL
    allow_methods = ["POST"]
    # HTTP headers that origins can include in requests
    #allow_headers = ["content-type", "authorization"]
    allow_headers = ["x-hub-signature-256", "content-type"]
    # Whether to allow cookies or other credentials (optional, default is false)
    allow_credentials = false
    # Maximum amount of time - set this to match webhook timeout
    max_age = 10
    }
}

# Explicitly grant public access permission to the function URL
resource "aws_lambda_permission" "allow_public_access" {
  statement_id     = "FunctionURLAllowPublicAccess"
  action           = "lambda:InvokeFunctionUrl"
  function_name    = aws_lambda_function.spot_runner.function_name
  principal        = "*" # Allows any caller
  # The function_url_auth_type condition is crucial for public access
  function_url_auth_type = "NONE"
}

# Optional: Output the function name
output "lambda_function_name" {
  value = aws_lambda_function.spot_runner.function_name
}