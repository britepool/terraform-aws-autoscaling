provider "aws" {
  region = local.region

  # Make it faster by skipping something
  skip_get_ec2_platforms      = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

locals {
  name   = "example-launch-template"
  region = "eu-west-1"

  tags = [
    {
      key                 = "Project"
      value               = "megasecret"
      propagate_at_launch = true
    },
    {
      key                 = "foo"
      value               = ""
      propagate_at_launch = true
    },
  ]

  tags_as_map = {
    Owner       = "user"
    Environment = "dev"
  }

  user_data = <<-EOT
  #!/bin/bash
  echo "Hello Terraform!"
  EOT
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2"

  name = local.name
  cidr = "10.99.0.0/18"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  public_subnets  = ["10.99.0.0/24", "10.99.1.0/24", "10.99.2.0/24"]
  private_subnets = ["10.99.3.0/24", "10.99.4.0/24", "10.99.5.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags_as_map
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 3"

  name        = local.name
  description = "A security group"
  vpc_id      = module.vpc.vpc_id

  egress_rules = ["all-all"]

  tags = local.tags_as_map
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name = "name"

    values = [
      "amzn-ami-hvm-*-x86_64-gp2",
    ]
  }
}

resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
  description      = "A service linked role for autoscaling"
  custom_suffix    = local.name

  # Sometimes good sleep is required to have some IAM resources created before they can be used
  provisioner "local-exec" {
    command = "sleep 10"
  }
}

################################################################################
# Default
################################################################################

module "default" {
  source = "../../"

  # Autoscaling group
  name = "default-${local.name}"

  vpc_zone_identifier = module.vpc.private_subnets
  min_size            = 0
  max_size            = 1
  desired_capacity    = 1

  # Launch template
  use_lt    = true
  create_lt = true

  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags        = local.tags
  tags_as_map = local.tags_as_map
}

################################################################################
# External
################################################################################

resource "aws_launch_template" "this" {
  name_prefix   = "external-${local.name}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  lifecycle {
    create_before_destroy = true
  }
}

module "external" {
  source = "../../"

  # Autoscaling group
  name = "external-${local.name}"

  vpc_zone_identifier = module.vpc.private_subnets
  min_size            = 0
  max_size            = 1
  desired_capacity    = 1

  # Launch template
  use_lt          = true
  launch_template = aws_launch_template.this.name

  tags        = local.tags
  tags_as_map = local.tags_as_map
}

# ################################################################################
# # Complete
# ################################################################################

# module "complete" {
#   source = "../../"

#   # Autoscaling group
#   name            = local.name
#   use_name_prefix = false

#   min_size                  = 0
#   max_size                  = 1
#   desired_capacity          = 1
#   wait_for_capacity_timeout = 0
#   health_check_type         = "EC2"
#   vpc_zone_identifier       = module.vpc.private_subnets
#   service_linked_role_arn   = aws_iam_service_linked_role.autoscaling.arn

#   # Launch template
#   lt_name   = "complete-${local.name}"
#   use_lt    = true
#   create_lt = true

#   ebs_optimized = true
#   image_id      = data.aws_ami.amazon_linux.id
#   instance_type = "t3.micro"
#   user_data     = local.user_data

#   security_groups             = [module.security_group.this_security_group_id]
#   associate_public_ip_address = true

#   ebs_block_device = [
#     {
#       device_name           = "/dev/xvdz"
#       delete_on_termination = true
#       encrypted             = true
#       volume_type           = "gp2"
#       volume_size           = "50"
#     },
#   ]

#   root_block_device = [
#     {
#       delete_on_termination = true
#       encrypted             = true
#       volume_size           = "50"
#       volume_type           = "gp2"
#     },
#   ]

#   metadata_options = {
#     http_endpoint               = "enabled"
#     http_tokens                 = "required"
#     http_put_response_hop_limit = 32
#   }

#   tags        = local.tags
#   tags_as_map = local.tags_as_map
# }
