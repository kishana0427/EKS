# VPC
resource "aws_vpc" "mrcet_eks_vpc" {
  cidr_block = "192.168.0.0/16"

  tags = {
    Name = "mrcet-eks-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.mrcet_eks_vpc.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnets
resource "aws_subnet" "eks_subnet_public" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.mrcet_eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.mrcet_eks_vpc.cidr_block, 8, count.index + 1)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-subnet-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnets
resource "aws_subnet" "eks_subnet_private" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.mrcet_eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.mrcet_eks_vpc.cidr_block, 8, count.index + 4)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "eks-subnet-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "eks_nat_eip" {
  count = length(data.aws_availability_zones.available.names)
  #vpc   = true
  tags = {
    Name = "eks-nat-eip-${count.index + 1}"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "eks_nat_gateway" {
  count         = length(data.aws_availability_zones.available.names)
  allocation_id = aws_eip.eks_nat_eip[count.index].id
  subnet_id     = aws_subnet.eks_subnet_public[count.index].id
  depends_on    = [aws_internet_gateway.eks_igw]
}

# Route tables for public
resource "aws_route_table" "eks_public_rt" {
  vpc_id = aws_vpc.mrcet_eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }
}

resource "aws_route_table_association" "eks_public_rta" {
  count        = length(data.aws_availability_zones.available.names)
  subnet_id    = aws_subnet.eks_subnet_public[count.index].id
  route_table_id = aws_route_table.eks_public_rt.id
}

# Route tables for private
resource "aws_route_table" "eks_private_rt" {
  count       = length(data.aws_availability_zones.available.names)
  vpc_id      = aws_vpc.mrcet_eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat_gateway[count.index].id
  }
}

resource "aws_route_table_association" "eks_private_rta" {
  count        = length(data.aws_availability_zones.available.names)
  subnet_id    = aws_subnet.eks_subnet_private[count.index].id
  route_table_id = aws_route_table.eks_private_rt[count.index].id
}

# IAM Role for EKS
resource "aws_iam_role" "eks_role" {
  name = "${var.cluster_name}-eks-role"

  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}




resource "aws_security_group" "eks_control_plane_sg" {
  vpc_id = aws_vpc.mrcet_eks_vpc.id

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }

  tags = {
    Name = "eks-control-plane-sg"
  }
}


# EKS Cluster
resource "aws_eks_cluster" "mrcet_eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_role.arn
  version  = "1.29"

  vpc_config {
    subnet_ids = aws_subnet.eks_subnet_private[*].id
  }
  

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSServicePolicy
  ]
}

# Node group role
resource "aws_iam_role" "node_group_role" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = data.aws_iam_policy_document.eks_nodes_assume_role.json
}

data "aws_iam_policy_document" "eks_nodes_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  role       = aws_iam_role.node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "cni_policy" {
  role       = aws_iam_role.node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "registry_policy" {
  role       = aws_iam_role.node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Node Group
resource "aws_eks_node_group" "mrcet_eks_node_group" {
  cluster_name    = aws_eks_cluster.mrcet_eks_cluster.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = aws_subnet.eks_subnet_private[*].id  # Use private subnets

  scaling_config {
    desired_size = 2   # Temporarily reduce the desired size to 1
    max_size     = 3
    min_size     = 2
  }

  instance_types = ["t3.medium"]  # Changed instance type to t3.small
  capacity_type  = "SPOT"        # Use Spot Instances to potentially bypass fleet request limits

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.cni_policy,
    aws_iam_role_policy_attachment.registry_policy
  ]
}

