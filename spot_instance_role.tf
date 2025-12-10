# The provider configuration is assumed in a separate file or block.
# provider "aws" {
#   region = "us-east-1"
# }

# Create the policy document to be later assumed by the role
data "aws_iam_policy_document" "gh_assume_role" {
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
      values   = ["repo:AndrewSimon/tf-files:*"]
    }
  }
}

data "aws_caller_identity" "current" {}

# IAM Role that the EC2 instance will assume
resource "aws_iam_role" "spot_instance_role" {
  name = "spot_instance_role"
  assume_role_policy = data.aws_iam_policy_document.gh_assume_role.json
}

# IAM policy for the spot instance requests with specific conditions
resource "aws_iam_policy" "spot_policy" {
  name        = "spot_policy"
  description = "Allows creation/running of only one t3a.micro spot instance in us-east-1f"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowSpotInstanceCreationWithConditions",
        Effect = "Allow",
        Action = [
          "ec2:RequestSpotInstances",
          "ec2:RunInstances" # RequestSpotInstances might use RunInstances internally
        ],
        Resource = "*", # Resource-level permissions might not be supported for RequestSpotInstances condition keys
        Condition = {
          "StringEquals" = {
            "ec2:InstanceType"        = "t3a.micro",
            "ec2:PlacementAvailabilityZone" = "us-east-1f"
          },
          "NumericLessThanEquals" = {
            "ec2:TotalSpotInstanceCount" = 1
          }
        }
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

output "assume_role_policy_document" {
  value = data.aws_iam_role.spot_instance_role.assume_role_policy
}