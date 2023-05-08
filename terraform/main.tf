data "aws_availability_zones" "available" {
}

data "aws_ami" "latest_amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-2*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

locals {
  cluster_name    = "eks-lab-01"
  cluster_version = "1.26"
  vpc_name        = "vpc-k8s"
}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  name                 = local.vpc_name
  cidr                 = "172.16.0.0/16"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets       = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  private_subnets      = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  database_subnets     = ["172.16.7.0/24", "172.16.8.0/24", "172.16.9.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_security_group" "ec2_bastion" {
  name        = "sgr-ec2-bastion"
  description = "Bastion EC2 security group"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sgr-ec2-bastion"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "db" {
  name        = "sgr-rds-db"
  description = "Allow MySQL inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sgr-rds-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "efs" {
  name        = "sgr-efs-filesystem"
  description = "Allow NFS inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "NFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sgr-efs"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_policy" "policy_eks_full_access" {
  name = "policy-eks-full-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["eks:*"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:*::parameter/aws/*"
      },
      {
        Action   = ["kms:CreateGrant", "kms:DescribeKey"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["logs:PutRetentionPolicy"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_policy" "iam_limited_access" {
  name        = "policy-iam-limited-access"
  description = "IAM policy for bastion"

  policy = file("iam-policy-iam-limited-permissions.json")
}

resource "aws_iam_role" "ec2_bastion_iam_role" {
  name = "role-bastion-ec2"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    aws_iam_policy.iam_limited_access.arn,
    aws_iam_policy.policy_eks_full_access.arn
  ]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "RoleForEC2"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_bastion_instance_profile" {
  name = "role-bastion-ec2"
  role = aws_iam_role.ec2_bastion_iam_role.name
}

resource "aws_instance" "bastion_host" {
  ami                    = data.aws_ami.latest_amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.private_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.ec2_bastion_instance_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_bastion.id]

  root_block_device {
    encrypted = true
  }
  user_data = <<-EOF
                #!/bin/bash
                su - ec2-user
                yum update -y
                curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.26.2/2023-03-17/bin/linux/amd64/kubectl
                chmod +x ./kubectl
                mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
                echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
                EOF
  tags = {
    Name = "i-bastion-host"
  }
}

resource "aws_iam_policy" "worker_policy_efs" {
  name        = "policy-efs-worker-nodes"
  description = "Worker policy for the EFS"

  policy = file("iam-policy-efs-controller.json")
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name                    = local.cluster_name
  cluster_version                 = local.cluster_version
  cluster_enabled_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    iam_role_attach_cni_policy = true
  }

  cluster_security_group_additional_rules = {
    ingress_bastion_host = {
      description              = "Ingress from the bastion security group"
      protocol                 = "-1"
      from_port                = 0
      to_port                  = 0
      type                     = "ingress"
      source_security_group_id = aws_security_group.ec2_bastion.id
    }
  }

  eks_managed_node_groups = {
    managed-node-group-01 = {
      min_size     = 1
      max_size     = 4
      desired_size = 2

      instance_types = ["t3.medium"]
      iam_role_additional_policies = {
        policy-managed-node-group-efs = aws_iam_policy.worker_policy_efs.arn
        AmazonSSMManagedInstanceCore  = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  kms_key_owners = [aws_iam_role.ec2_bastion_iam_role.arn]

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.ec2_bastion_iam_role.arn
      username = aws_iam_role.ec2_bastion_iam_role.name
      groups   = ["system:masters"]
    },
  ]

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "rds subnet group"
  subnet_ids = [module.vpc.database_subnets[0], module.vpc.database_subnets[1], module.vpc.database_subnets[2]]

  tags = {
    Name = "DB subnet group"
  }
}

resource "aws_db_instance" "rds_wp" {
  engine                 = "mysql"
  identifier             = "wordpress-db"
  username               = var.db_user_name
  password               = var.db_password
  instance_class         = "db.t3.micro"
  storage_type           = "gp2"
  multi_az               = true
  allocated_storage      = 10
  db_subnet_group_name   = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db.id]
  storage_encrypted      = true
  skip_final_snapshot    = true
  db_name                = "wordpressdb"
}

resource "aws_efs_file_system" "efs" {
  encrypted = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "efs-eks"
  }
}

resource "aws_efs_mount_target" "efs-mount-1" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "efs-mount-2" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = module.vpc.private_subnets[1]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "efs-mount-3" {
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = module.vpc.private_subnets[2]
  security_groups = [aws_security_group.efs.id]
}