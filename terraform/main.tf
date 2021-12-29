data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
}

locals {
  cluster_name = "eks-cluster"
}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  name                 = "k8s-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_security_group" "public_ssh" {
  name        = "allow_public_ssh_traffic"
  description = "Allow ssh inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_public_ssh"
  }
}

resource "aws_security_group" "private_eks" {
  name        = "allow_private_eks_traffic"
  description = "Allow ssh and http inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/16"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
    Name = "allow_eks_communication"
  }
}

resource "aws_security_group" "db" {
  name        = "allow_db_traffic"
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
    Name = "allow_db_traffic"
  }
}

resource "aws_security_group" "efs" {
  name        = "allow_nfs_traffic"
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
    Name = "allow_nfs_traffic"
  }
}

module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_name                    = local.cluster_name
  cluster_version                 = "1.21"
  subnets                         = module.vpc.private_subnets
  cluster_endpoint_private_access = true
  vpc_id                          = module.vpc.vpc_id
  workers_additional_policies     = [aws_iam_policy.worker_policy_efs.arn]

  worker_groups = [
    {
      instance_type                 = "t3.medium"
      asg_max_size                  = 5
      asg_desired_capacity          = 3
      additional_security_group_ids = [aws_security_group.private_eks.id]
      key_name                      = var.key_pair
    }
  ]
}

resource "aws_iam_policy" "worker_policy_efs" {
  name        = "worker-policy-efs"
  description = "Worker policy for the EFS"

  policy = file("iam-policy-efs-controller.json")
}

resource "aws_eip" "eip" {
  vpc        = true
  depends_on = [module.vpc]
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.bastion-host.id
  allocation_id = aws_eip.eip.id
}

resource "aws_instance" "bastion-host" {
  ami                    = "ami-0ed9277fb7eb570c9"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.public_ssh.id]
  subnet_id              = module.vpc.public_subnets[0]
  key_name               = var.key_pair
  root_block_device {
    encrypted = true
  }
  user_data = <<-EOF
                #!/bin/bash
                sudo yum update -y
                EOF
  tags = {
    Name = "bastion-host"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "rds subnet group"
  subnet_ids = [module.vpc.private_subnets[0], module.vpc.private_subnets[1], module.vpc.private_subnets[2]]

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
  name                   = "wordpressdb"
}

resource "aws_efs_file_system" "efs" {
  encrypted = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "eks-efs"
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