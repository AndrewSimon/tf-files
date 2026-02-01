# Terraform spot_instance_role.tf
## 1) Create Trust policy enabling OIDC from gh with (source) conditions
## 2) Create Trust policy enabling SSM to interact with ec2 instances
## 3) Creates an ec2 policy lambda uses and attaches policies to the role
## 4) Creates the spot instance profile with/from the spot instance role

data "aws_iam_policy_document" "gh_ssm_assume_role" {
  statement {
    effect = "Allow"    
    principals {
      type    = "Service"
      identifiers = ["ec2.amazonaws.com"]
      }
    actions = ["sts:AssumeRole"]
  }
  
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repo_name}:*"]
    }
  } 
}

data "aws_caller_identity" "current" {}

# IAM Role that the EC2 instance will assume
resource "aws_iam_role" "spot_instance_role" {
  name = "spot_instance_role"
  assume_role_policy = data.aws_iam_policy_document.gh_ssm_assume_role.json
}

# IAM policy for the spot instance requests with specific conditions
resource "aws_iam_policy" "spot_policy" {
  name        = "spot_policy"
  description = "Allows creation/running of only one t3a.micro spot instance in us-east-1f"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowInstanceCreationAndTermination",
        Effect = "Allow",
        Action = [
          "ec2:RequestSpotInstances",
          "ec2:TerminateInstances",
          "ec2:RunInstances" # RequestSpotInstances might use RunInstances internally
        ],
        Resource = "arn:aws:ec2:*:*:instance/*", 
      },
      {
        Sid    = "AllowRequiredDescribeActions",
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeTags",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeImages",
          "ec2:DescribeSubnets"       
        ],
        Resource = "*"
      },
      {
        Sid = "AllowPassingRoleToLambda",
        Effect = "Allow",
        Action = "iam:PassRole",
        Resource = aws_iam_role.spot_instance_role.arn
      },
      {
        Sid = "AllowPassingRoleToEC2",
        Effect = "Allow",
        Action = "iam:PassRole",
        Resource = aws_iam_role.spot_instance_role.arn
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetBucketLocation", 
          "s3:ListBucket"
        ],
        Resource = "arn:aws:s3:::win11-tlc" 
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "spot_policy_attachment" {
  role       = aws_iam_role.spot_instance_role.name
  policy_arn = aws_iam_policy.spot_policy.arn
}

# IAM Instance Profile (required to attach role to an EC2 instance)
resource "aws_iam_instance_profile" "spot_instance_profile" {
  name = "spot_instance_profile"
  role = aws_iam_role.spot_instance_role.name
}

output "role_arn" {
  value = data.aws_iam_role.spot_instance_role.arn
}

data "aws_iam_role" "spot_instance_role" {
  name = "spot_instance_role"
}

resource "aws_iam_instance_profile" "spot_profile" {
  name = "spot_profile"
  role = aws_iam_role.spot_instance_role.name
}
