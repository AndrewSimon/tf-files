#resource "local_file" "ssm" {
#  filename = "ssm.yaml"
#  content  = <<-EOT
#schemaVersion: "2.2"
#description: "Add SSH public key to ec2-user, then config and run runner"
#mainSteps:
#  - action: "aws:runShellScript"
#    name: "AddSshKeyAndRunCommands"
#    inputs:
#      runCommand:
#        - |
#          # Ensure .ssh directory exists and has correct permissions
#          sudo mkdir -p /home/ec2-user/.ssh
#          sudo chmod 700 /home/ec2-user/.ssh
#          
#          # Add the public key to authorized_keys (replace with your actual key)
#          # Use 'cat >>' to append, preventing overwrite if other keys exist
#          PUB_KEY="${file(var.public_key_path)}"
#          echo "$PUB_KEY" | sudo tee -a /home/ec2-user/.ssh/authorized_keys > /dev/null
#          
#          # Set correct ownership and permissions for authorized_keys file
#          sudo chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
#          sudo chmod 600 /home/ec2-user/.ssh/authorized_keys
#          
#          # --- Your additional bash commands below ---
#          echo "Configuring and starting runner..."
#          export TAG_KEY="GH_REG_TOKEN"
#          export TOKEN=$(curl -X PUT "169.254.169.254" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
#          export RUNNER_TOKEN=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v 169.254.169.254/latest/meta-data/tags/instance/GH_REG_TOKEN 2>/dev/null)
#          sudo -u gh-runner bash -c "cd /home/gh-runner && ./config.sh --url https://github.com/AndrewSimon/tf-files --token $RUNNER_TOKEN --unattended --replace --name tlc-spot-runner"
#          nohup sudo -u gh-runner bash -c 'cd /home/gh-runner && ./run.sh' &
#
#          echo "Finished running commands."
#EOT
#  file_permission = "0755"
#}

# Read the content of the YAML file
#data "local_file" "ssm_document_content" {
#  filename = "${path.module}/ssm.yaml"
#  depends_on = [
#    local_file.ssm
#  ]
#}

# Note: This rule captures ALL spot and on-demand running instances
# We can tell ssm to filter on tags later 
#resource "aws_cloudwatch_event_rule" "spot_instance_rule" {
#  name_prefix   = "spot-instance-rule-"
#  description   = "Capture EC2 spot instance creation events"
#  event_pattern = jsonencode({
#    "source": ["aws.ec2"],
#    "detail-type": ["EC2 Instance State Change"],
#    "detail": {
#      "eventSource": ["ec2.amazonaws.com"],
#      "eventName": ["RunInstances"],
#      "state": ["running"]
#     }
#  })
#}

# Define the EventBridge Target to run an SSM Document (baased on tags)
#resource "aws_cloudwatch_event_target" "ssm_target" {
#  rule      = aws_cloudwatch_event_rule.spot_instance_rule.name
#  arn       = "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript" # Use a standard or custom SSM Document ARN
#  role_arn  = aws_iam_role.events_ssm_role.arn

#   run_command_targets {
#     key    = "tag:runner"
#     values = ["true"] # Target instances with a specific tag
#   }
#}

# Define the IAM Role for the EventBridge target to run SSM commands
#resource "aws_iam_role" "events_ssm_role" {
#  name = "EventBridgeSSMRole"

#  assume_role_policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Effect = "Allow"
#        Principal = {
#          Service = "events.amazonaws.com"
#  
#        }
#        Action = "sts:AssumeRole"
#      }
#    ]
#  })
#}

## Attach a policy to the role allowing it to use SSM Run Command
#resource "aws_iam_role_policy" "events_ssm_policy" {
#  name = "events-ssm-policy"
#  role = aws_iam_role.events_ssm_role.id

#  policy = jsonencode({
#    Version = "2012-10-17"
#    Statement = [
#      {
#        Effect = "Allow"
#        Action = [
#          "ssm:SendCommand",
#          "ssm:ListCommands",
#          "ssm:ListCommandInvocations",
#          "ec2:DescribeInstances" # Needed by some SSM documents
#        ]
#        Resource = "*" # Restrict this to specific resources in a production environment
#      }
#    ]
#  })
#}

# --- Required IAM Role/Profile for SSM ---

resource "aws_iam_role" "ssm_role" {
#  name = "EC2SSMRoleForSSHKey"
  name = "EC2SSMRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy" "ssm_default_policy" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_iam_role" "ssm_default_host_management_role" {
  name = "AWSSystemsManagerDefaultEC2InstanceManagementRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_default_host_management_attachment" {
  role       = aws_iam_role.ssm_default_host_management_role.name
  policy_arn = data.aws_iam_policy.ssm_default_policy.arn
}

# The actual configuration that tells the account/region to use this role as default
# is not available as a direct Terraform resource. Please add manually.ssh root


resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  # This AWS managed policy grants necessary permissions for SSM
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "EC2SSMInstanceProfileForSSHKey"
  role = aws_iam_role.ssm_role.name
}
