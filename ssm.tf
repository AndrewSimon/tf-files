# Attach the SSM policy arn to EC2 Trust policy in spot_instance_role.tf
resource "aws_iam_role_policy_attachment" "SSMPolicy_attachment" {
  role       = aws_iam_role.spot_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

