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
  description = "EKS cluster SG"
  vpc_id      = aws_vpc.eks_vpc.id
}

# EKS Node Security Group

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
    ec2_ssh_key               = "kavitha-home-2025" # Optional: Replace with actual key pair name
    source_security_group_ids = [aws_security_group.eks_node_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_worker_node_policies]
  
}

########################
# 5. Cluster Autoscaler (Kubernetes Level)
########################

helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set cloudProvider=aws \
  --set autoDiscovery.clusterName=my-eks-cluster \
  --set awsRegion=ap-south-1 \
  --set rbac.create=true \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.expander=least-waste \
  --set extraArgs.skip-nodes-with-local-storage=false \
  --set extraArgs.skip-nodes-with-system-pods=false
   terraform plan
╷
│ Error: Unsupported block type
│
│   on main.tf line 235:
│  235: helm repo add autoscaler https://kubernetes.github.io/autoscaler
│
│ Blocks of type "helm" are not expected here.
╵
╷
│ Error: Invalid block definition
│
│   on main.tf line 235:
│  235: helm repo add autoscaler https://kubernetes.github.io/autoscaler
│
│ Either a quoted string block label or an opening brace ("{") is expected here.
╵
╷
│ Error: Unsupported block type
│
│   on main.tf line 236:
│  236: helm repo update
│
│ Blocks of type "helm" are not expected here.
╵
╷
│ Error: Invalid block definition
│
│   on main.tf line 236:
│  236: helm repo update
│
│ A block definition must have block content delimited by "{" and "}", starting on the same line as the block header.
╵
╷
│ Error: Unsupported block type
│
│   on main.tf line 238:
│  238: helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
│
│ Blocks of type "helm" are not expected here.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 238:
│  238: helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 239:
│  239:   --namespace kube-system \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 240:
│  240:   --set cloudProvider=aws \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 241:
│  241:   --set autoDiscovery.clusterName=my-eks-cluster \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 242:
│  242:   --set awsRegion=ap-south-1 \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 243:
│  243:   --set rbac.create=true \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 244:
│  244:   --set extraArgs.balance-similar-node-groups=true \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 245:
│  245:   --set extraArgs.expander=least-waste \
│
│ This character is not used within the language.
╵
╷
│ Error: Invalid character
│
│   on main.tf line 246:
│  246:   --set extraArgs.skip-nodes-with-local-storage=false \
│
│ This character is not used within the language.



You're getting all those Terraform errors because you're trying to run Helm CLI commands (helm repo add, helm upgrade, etc.) inside a Terraform configuration file (main.tf). Terraform does not understand or accept CLI commands written like shell script in .tf files — it expects resource definitions written in Terraform syntax.
✅ Correct Approach:

If you want to install the Cluster Autoscaler using Helm in Terraform, you need to use the helm_release resource from the Terraform Helm provider.
🛠️ How to fix it (Terraform-native Helm install):

First, make sure you declare the Helm provider in your configuration:

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config" # or use a data source if provisioning kubeconfig
  }
}


Then, add this Terraform block to install the Cluster Autoscaler via Helm:


resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.0" # Replace with latest or needed version

  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = "my-eks-cluster"
  }

  set {
    name  = "awsRegion"
    value = "ap-south-1"
  }

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }

  set {
    name  = "extraArgs.skip-nodes-with-local-storage"
    value = "false"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }
}


✅ Summary

    ❌ Don’t write CLI commands like helm install ... inside main.tf

    ✅ Use the helm_release resource to install Helm charts

    ✅ Add the Helm provider

    ✅ Ensure your kubeconfig is available to the Helm provider


    Let me know if you want to configure the provider dynamically (e.g., using Terraform output from your EKS cluster for the kubeconfig).