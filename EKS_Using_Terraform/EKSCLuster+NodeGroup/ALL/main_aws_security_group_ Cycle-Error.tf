#####################
# 1. VPC & Networking
#####################

# VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "eks-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
}

# Public Subnets (2)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)

  tags = {
    Name = "eks-public-${count.index}"
  }
}

# Private Subnets (2)
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index + 2)
  map_public_ip_on_launch = false
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)

  tags = {
    Name = "eks-private-${count.index}"
  }
}

# NAT Gateway Elastic IPs
resource "aws_eip" "nat_eip" {
  count      = 2
  depends_on = [aws_internet_gateway.igw]
}

# NAT Gateways (1 per AZ)
resource "aws_nat_gateway" "nat_gw" {
  count         = 2
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Private Route Tables (1 per subnet)
resource "aws_route_table" "private_rt" {
  count  = 2
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw[count.index].id
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt[count.index].id
}

########################
# 2. Security Groups
########################

# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster_sg" {
  name        = "eks-cluster-sg"
  description = "Security group for EKS Cluster"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description     = "Allow worker nodes to communicate with cluster API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_node_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-cluster-sg"
  }
}

# EKS Node Security Group
resource "aws_security_group" "eks_node_sg" {
  name        = "eks-node-sg"
  description = "Security group for EKS Worker Nodes"
  vpc_id      = aws_vpc.eks_vpc.id

  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "Allow nodes to talk to EKS Cluster"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-node-sg"
  }
}

########################
# 3. IAM Roles & Policies
########################

# EKS Cluster Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "eks.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach policies to EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_cluster_attach" {
  count      = 2
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  ], count.index)
}

# EKS Node Group Role
resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeGroupRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach policies to Node Group Role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policies" {
  count      = 3
  role       = aws_iam_role.eks_node_role.name
  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  ], count.index)
}

########################
# 4. EKS Cluster & Node Group
########################

# EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "my-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.33"

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_attach]
}

# EKS Managed Node Group
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "my-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.micro"]
  capacity_type  = "SPOT"
  ami_type       = "AL2023_x86_64_STANDARD"

  remote_access {
    ec2_ssh_key               = "your-ssh-key-name" # Optional: Replace with actual key pair name
    source_security_group_ids = [aws_security_group.eks_node_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_worker_node_policies]
}


terraform validate
╷
│ Error: Cycle: aws_security_group.eks_node_sg, aws_security_group.eks_cluster_sg
│
│
╵
ubuntu@ip-172-31-5-185:~/terraform$ terraform plan
╷
│ Error: Cycle: aws_security_group.eks_cluster_sg, aws_security_group.eks_node_sg

The error you're seeing:

Error: Cycle: aws_security_group.eks_cluster_sg, aws_security_group.eks_node_sg


...means Terraform has detected a circular dependency between the two security groups: eks_cluster_sg and eks_node_sg.

This typically happens when each resource references the other in a way that Terraform cannot resolve a valid creation order.


🔍 Common Cause

You likely have something like this in your Terraform configuration:

resource "aws_security_group" "eks_cluster_sg" {
  # ...
  ingress {
    # Reference to eks_node_sg
    security_groups = [aws_security_group.eks_node_sg.id]
  }
}

resource "aws_security_group" "eks_node_sg" {
  # ...
  ingress {
    # Reference to eks_cluster_sg
    security_groups = [aws_security_group.eks_cluster_sg.id]
  }
}


In this case, Terraform doesn’t know which one to create first because each one depends on the other.


✅ Solution

To fix the circular dependency, break the direct dependency loop. You can do this by:
✅ Option 1: Use aws_security_group_rule Resources

Instead of defining ingress rules inline, define the security groups first (without referencing each other), and then add rules separately using aws_security_group_rule.

Example:

resource "aws_security_group" "eks_cluster_sg" {
  name        = "eks-cluster-sg"
  description = "EKS cluster SG"
  vpc_id      = aws_vpc.eks_vpc.id
}

resource "aws_security_group" "eks_node_sg" {
  name        = "eks-node-sg"
  description = "EKS node SG"
  vpc_id      = aws_vpc.eks_vpc.id
}

# Allow nodes to talk to cluster
resource "aws_security_group_rule" "node_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster_sg.id
  source_security_group_id = aws_security_group.eks_node_sg.id
}

# Allow cluster to talk to nodes
resource "aws_security_group_rule" "cluster_to_node" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node_sg.id
  source_security_group_id = aws_security_group.eks_cluster_sg.id
}


By using separate aws_security_group_rule resources, you avoid Terraform trying to resolve 
both at the same time — because the groups are created first, then the rules are added.




