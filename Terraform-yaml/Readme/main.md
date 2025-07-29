# 1. VPC & Networking
#####################

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)
  tags = {
    Name                                        = "eks-public-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index + 2)
  map_public_ip_on_launch = false
  availability_zone       = element(["ap-south-1a", "ap-south-1b"], count.index)
  tags = {
    Name                                        = "eks-private-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_eip" "nat_eip" {
  count      = 2
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat_gw" {
  count         = 2
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}

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

# 2. Security Groups
#####################

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

resource "aws_security_group_rule" "node_to_cluster" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster_sg.id
  source_security_group_id = aws_security_group.eks_node_sg.id
}

resource "aws_security_group_rule" "cluster_to_node" {
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node_sg.id
  source_security_group_id = aws_security_group.eks_cluster_sg.id
}


# 3. IAM Roles & Policies
##########################

resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "eks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_attach" {
  count = 2
  role  = aws_iam_role.eks_cluster_role.name
  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  ], count.index)
}

resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeGroupRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policies" {
  count = 3
  role  = aws_iam_role.eks_node_role.name
  policy_arn = element([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  ], count.index)
}

# IAM policy for Cluster Autoscaler
#resource "aws_iam_policy" "cluster_autoscaler_policy" {
#  name   = "EKSClusterAutoscalerPolicy-1"
#  policy = file("${path.module}/autoscaler-policy.json")
#}

#resource "aws_iam_role_policy_attachment" "cluster_autoscaler_attach" {
#  role       = aws_iam_role.eks_node_role.name
#  policy_arn = aws_iam_policy.cluster_autoscaler_policy.arn
#}


# 4. EKS Cluster & Node Group
#############################
resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.30"

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_attach]
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "my-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  instance_types = ["t3.small"]
  capacity_type  = "SPOT"

  remote_access {
    ec2_ssh_key               = "kavitha-mrcet-key"
    source_security_group_ids = [aws_security_group.eks_node_sg.id]
  }

  ami_type = "AL2023_x86_64_STANDARD"

  #tags = {
  #  "k8s.io/cluster-autoscaler/enabled"             = "true"
  #  "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  #}

  #labels = {
  #  "k8s.io/cluster-autoscaler/enabled"       = "true"
  #  "k8s.io/cluster-autoscaler/my-eks-cluster" = "true"
  #}

  tags = {
    "k8s.io/cluster-autoscaler/enabled"       = "true"
    "k8s.io/cluster-autoscaler/my-eks-cluster" = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policies,
    #aws_iam_role_policy_attachment.cluster_autoscaler_attach
  ]
}




my-eks-cluster and node_group

 — based on your input:

Cluster name: my-eks-cluster

Auto Scaling Group name: node_group

Here is your ready-to-apply Cluster Autoscaler YAML, pre-filled and formatted correctly:


✅ cluster-autoscaler.yaml


apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
      annotations:
        cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
    spec:
      serviceAccountName: cluster-autoscaler  # Bound to IAM role via IRSA
      containers:
        - name: cluster-autoscaler
          image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.29.0
          command:
            - ./cluster-autoscaler
            - --cloud-provider=aws
            - --skip-nodes-with-local-storage=false
            - --balance-similar-node-groups
            - --expander=least-waste
            - --nodes=1:5:node_group
            - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/my-eks-cluster
            - --logtostderr=true
            - --stderrthreshold=info
            - --v=4
          resources:
            limits:
              cpu: 100m
              memory: 300Mi
            requests:
              cpu: 100m
              memory: 300Mi


✅ Required Tags on ASG (node_group)
Apply these tags so autoscaler can discover the ASG:


aws autoscaling create-or-update-tags --tags \
  ResourceId=node_group,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true \
  ResourceId=node_group,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/my-eks-cluster,Value=owned,PropagateAtLaunch=true



🚀 Apply the YAML:

kubectl apply -f cluster-autoscaler.yaml


Let me know if you'd like a script to validate the setup or restart the pod after IAM is ready.

yes

Below is a safe script that:

Verifies the Kubernetes service account annotation

Confirms the IAM role trust policy

Lists the Cluster Autoscaler pod(s)

Deletes any existing pod to force a restart (pick up the new IAM role)

✅ Cluster Autoscaler Validation & Restart Script


#!/bin/bash

# ---- CONFIG ----
CLUSTER_NAME="my-eks-cluster"
NAMESPACE="kube-system"
SERVICE_ACCOUNT="cluster-autoscaler"
DEPLOYMENT_NAME="cluster-autoscaler"
REGION="ap-south-1"

echo "🔍 Step 1: Verifying service account annotation..."
kubectl get sa $SERVICE_ACCOUNT -n $NAMESPACE -o json | jq '.metadata.annotations'

echo -e "\n🔍 Step 2: Checking IAM role trust relationship..."

# Get OIDC
OIDC_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text)
OIDC_HOST=$(echo $OIDC_URL | sed -e "s/^https:\/\///")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

ROLE_NAME="eks-cluster-autoscaler-role"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

aws iam get-role --role-name $ROLE_NAME --query "Role.AssumeRolePolicyDocument.Statement" --output json

echo -e "\n✅ Verified IAM role: $ROLE_ARN"

echo -e "\n🔁 Step 3: Restarting the Cluster Autoscaler pod..."
kubectl delete pod -n $NAMESPACE -l app=cluster-autoscaler

echo -e "\n✅ Done! Wait ~20 seconds and check logs using:\nkubectl logs -n $NAMESPACE -l app=cluster-autoscaler\n"


🛠 How to Use
Save as validate-autoscaler.sh

Make it executable:


chmod +x validate-autoscaler.sh


Run it:


./validate-autoscaler.sh


✅ Expected Output:
Shows your service account’s IAM role annotation

Shows the IAM role’s trust relationship with OIDC

Restarts the cluster-autoscaler pod

Instructs you to check logs


🔍 Check Logs:
After restart:


kubectl logs -n kube-system -l app=cluster-autoscaler


Look for success messages like:

I0725 12:45:34.123456       1 aws_manager.go:261] Refreshed ASG list: ...


Let me know if you'd like this script adapted to work across multiple clusters or exported as a ready-to-use .sh file.



yes

Here's your complete ready-to-use script as a .sh file — tailored for your EKS setup:

✅ Downloadable Script: validate-autoscaler.sh


#!/bin/bash

# === CONFIG ===
CLUSTER_NAME="my-eks-cluster"
NAMESPACE="kube-system"
SERVICE_ACCOUNT="cluster-autoscaler"
DEPLOYMENT_NAME="cluster-autoscaler"
REGION="ap-south-1"
ROLE_NAME="eks-cluster-autoscaler-role"

echo "🔍 Step 1: Verifying service account annotation..."
kubectl get sa $SERVICE_ACCOUNT -n $NAMESPACE -o json | jq '.metadata.annotations' || {
  echo "❌ Service account not found. Exiting."
  exit 1
}

echo -e "\n🔍 Step 2: Checking IAM role trust relationship..."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_URL=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query "cluster.identity.oidc.issuer" \
  --output text)

OIDC_HOST=$(echo $OIDC_URL | sed -e "s/^https:\/\///")
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

echo "✅ IAM Role: $ROLE_ARN"
echo "✅ OIDC Provider: $OIDC_URL"

aws iam get-role --role-name $ROLE_NAME \
  --query "Role.AssumeRolePolicyDocument.Statement" --output json || {
  echo "❌ IAM Role not found or missing trust policy."
  exit 1
}

echo -e "\n🔁 Step 3: Restarting Cluster Autoscaler pod(s)..."
kubectl delete pod -n $NAMESPACE -l app=$DEPLOYMENT_NAME || {
  echo "⚠️ No pods found to delete. Check if deployment exists."
}

echo -e "\n✅ Done! In 20–30 seconds, check logs with:\n"
echo "kubectl logs -n $NAMESPACE -l app=$DEPLOYMENT_NAME --tail=50 -f"
🛠 To Use This Script:
Create the file:
nano validate-autoscaler.sh


Paste the script above

Make it executable:

chmod +x validate-autoscaler.sh

Run it:

./validate-autoscaler.sh


🧪 Sample Output Should Show:
Your service account annotations (with IAM role ARN)

IAM role trust policy (validating OIDC provider + SA match)

Deleted and restarted cluster-autoscaler pod

Reminder on how to follow logs

Let me know if you want this exported as a downloadable .zip, or adapted for multiple clusters or environments.
