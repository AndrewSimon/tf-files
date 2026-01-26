# DHMC overrides instance roles. The needed additional configuration is out of scope here
#resource "aws_ssm_service_setting" "default_host_management" {
#  setting_id    = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
#  setting_value = "AWSSystemsManagerDefaultEC2InstanceManagementRole"
#}

resource "aws_iam_role_policy_attachment" "SSMPolicy_attachment" {
  role       = aws_iam_role.spot_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

