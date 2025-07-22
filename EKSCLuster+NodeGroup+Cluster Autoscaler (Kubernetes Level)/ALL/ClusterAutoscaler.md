Node group autoscaling
======================
======================



To enable autoscaling for EKS node groups, you need two layers of configuration:

✅ 1. EKS Managed Node Group Autoscaling (Terraform)

In your existing Terraform config (in main.tf), you're already defining scaling_config. 
Here's how to ensure it's correctly configured:

🔧 Example

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"  # or "SPOT"
}

✅ 2. Cluster Autoscaler (Kubernetes Level)

EKS doesn’t autoscale nodes by itself. To react to pod demand, you need to install the Cluster Autoscaler in your cluster.

🔧 Step-by-Step: Install Cluster Autoscaler (Helm Recommended)

First, make sure you declare the Helm provider in your configuration:

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config" # or use a data source if provisioning kubeconfig
  }
}

helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set cloudProvider=aws \
  --set autoDiscovery.clusterName=my-eks-cluster \
  --set awsRegion=us-east-1 \
  --set rbac.create=true \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.expander=least-waste \
  --set extraArgs.skip-nodes-with-local-storage=false \
  --set extraArgs.skip-nodes-with-system-pods=false

Or use a YAML manifest if you don’t want Helm.


If you prefer not to use Helm to install the Cluster Autoscaler on your EKS cluster, you can apply a YAML manifest directly. Below is a basic example of the manifest you can modify and apply using kubectl apply -f.
✅ Cluster Autoscaler Deployment YAML for AWS EKS (without Helm)

    Replace placeholders like my-eks-cluster, us-east-1, and the EKS node group tags accordingly.

apiVersion: v1
kind: ServiceAccount
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    k8s-addon: cluster-autoscaler.addons.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-autoscaler
rules:
  - apiGroups: [""]
    resources: ["events", "endpoints", "pods", "services", "nodes", "namespaces", "persistentvolumeclaims", "persistentvolumes"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["apps"]
    resources: ["replicasets", "statefulsets", "daemonsets", "deployments"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["autoscaling.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["extensions"]
    resources: ["replicasets", "daemonsets"]
    verbs: ["watch", "list", "get"]
  - apiGroups: ["policy"]
    resources: ["poddisruptionbudgets"]
    verbs: ["watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-autoscaler
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-autoscaler
subjects:
  - kind: ServiceAccount
    name: cluster-autoscaler
    namespace: kube-system
---
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
      serviceAccountName: cluster-autoscaler
      containers:
        - image: registry.k8s.io/autoscaling/cluster-autoscaler:v1.29.0
          name: cluster-autoscaler
          resources:
            limits:
              cpu: 100m
              memory: 600Mi
            requests:
              cpu: 100m
              memory: 600Mi
          command:
            - ./cluster-autoscaler
            - --cloud-provider=aws
            - --cluster-name=my-eks-cluster
            - --scan-interval=10s
            - --balance-similar-node-groups
            - --skip-nodes-with-local-storage=false
            - --skip-nodes-with-system-pods=false
            - --expander=least-waste
            - --aws-use-static-instance-list=false
            - --nodes=1:10:your-node-group-name
          volumeMounts:
            - name: ssl-certs
              mountPath: /etc/ssl/certs/ca-certificates.crt
              readOnly: true
          env:
            - name: AWS_REGION
              value: us-east-1
      volumes:
        - name: ssl-certs
          hostPath:
            path: /etc/ssl/certs/ca-bundle.crt

📌 Notes:

    Replace my-eks-cluster with your actual EKS cluster name.

    Replace your-node-group-name with the EKS managed node group name tagged with k8s.io/cluster-autoscaler/enabled = true and k8s.io/cluster-autoscaler/<cluster-name> = owned.

    Update the image tag (v1.29.0) as needed to match your Kubernetes version.

    Make sure your IAM Role (IRSA or node role) has permissions: autoscaling:DescribeAutoScalingGroups, autoscaling:SetDesiredCapacity, etc.

Let me know if you need the IRSA setup (IAM role and trust policy) as well.


📌 IAM for Cluster Autoscaler (IRSA Recommended)

Recommended: use IAM Roles for Service Accounts (IRSA) for autoscaler pods.

If not using IRSA, attach this policy to your node group role:

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}

✅ Summary
Component	What It Does
scaling_config	Sets min/max/desired capacity in Terraform
Cluster Autoscaler	Adds/removes nodes dynamically at runtime
IAM permissions	Grants Cluster Autoscaler access to manage ASGs
Optional: IRSA	Secure service account access to AWS APIs

To include the Cluster Autoscaler installation (Helm or YAML) and IAM policy attachment into your Terraform repo setup
======================================================================================================================

Below is the complete integration of Cluster Autoscaler into your Terraform EKS setup using:

    ✅ IAM Role for Service Account (IRSA)

    ✅ Helm-based deployment of Cluster Autoscaler

    ✅ Terraform-managed IAM policy

    ✅ Optional: Terraform Helm provider for autoscaler install

📁 Additions to GitHub Repo Structure

Add this to your repo under a new folder:

eks-cluster-terraform/
└── terraform/
    ├── cluster-autoscaler/
    │   ├── iam-policy.json

🔐 cluster-autoscaler/iam-policy.json


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}


✍️ Add to main.tf (IRSA + Helm)

1. IAM Policy & Role for Autoscaler

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "EKSClusterAutoscalerPolicy"
  policy      = file("${path.module}/cluster-autoscaler/iam-policy.json")
}

resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.cluster_name}-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler_attach" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

2. OIDC Provider for IRSA

data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

data "tls_certificate" "oidc" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}


📦 Optional: Install Cluster Autoscaler via Terraform Helm Provider

Add Helm provider block in provider.tf:

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}


Then add the Helm release:

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
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

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_autoscaler_attach]
}

✅ What You Get
Feature	Value
EKS Node Group Autoscaling	Scales nodes between min/max automatically
Cluster Autoscaler	Reacts to pod demand to increase/decrease node count
IAM for Autoscaler	Uses secure IRSA role with minimal permissions
Helm Deployed	Automatically installs via Terraform + Helm provider





======================================================================================================================
======================================================================================================================


what Cluster Autoscaler will do and diffrence from node_group scaling_config?

Great question. Let's clarify what the scaling_config in the aws_eks_node_group does, 
and then explain what Cluster Autoscaler adds on top of that.

📦 What You're Defining in scaling_config

This part in your aws_eks_node_group:

scaling_config {
  desired_size = 2
  max_size     = 5
  min_size     = 1
}

...is setting the initial and allowed limits for the number of nodes in your EKS node group, managed by AWS Auto Scaling. It controls:

    desired_size: Number of nodes to start with when the node group is created.

    min_size / max_size: The limits for how far scaling up/down is allowed, but AWS alone won't change it dynamically.

This setup does not enable autoscaling by itself — it's static unless something (like Cluster Autoscaler or manual intervention) changes it.
🚀 What the Cluster Autoscaler Does

Cluster Autoscaler is a Kubernetes component that:

    Automatically adds nodes to your cluster when:

        There are pods pending because of insufficient resources.

    Automatically removes nodes when:

        They are underutilized and no longer needed (and can be safely drained).

It runs inside your Kubernetes cluster as a deployment and interacts with the AWS Auto Scaling API to modify the desired node count — but only within the min_size and max_size limits you defined in your scaling_config.
🔍 Summary of Differences

Feature	                  scaling_config in Terraform	              Cluster Autoscaler
Who controls it?	        AWS (via Terraform config)	              Kubernetes controller (runs in-cluster)
Dynamic scaling?	        ❌ No (static unless changed manually)	  ✅ Yes (based on real-time resource needs)
Initial node count?	      ✅ Yes (via desired_size)	                ❌ No, but can change desired size later
Upscaling nodes?	        ❌ Not automatic	                        ✅ Yes
Downscaling unused nodes?	❌ Not automatic	                        ✅ Yes
Must stay within min/max?	✅ Yes	                                  ✅ Yes (respects limits)



✅ To Use Cluster Autoscaler

    Keep your scaling_config with reasonable min_size and max_size.

    Deploy the Cluster Autoscaler Helm chart into your cluster.

    Ensure:

        Your node group IAM role allows scaling actions.

        The nodes are labeled and tainted appropriately.

        You use --nodes=min:max:group-name arguments if you run it manually.

if you'd like a ready-to-use Helm chart or manifest for Cluster Autoscaler on EKS.

Here's a step-by-step guide to deploy Cluster Autoscaler on EKS using Helm, which is the recommended and simplest method.
✅ Step-by-Step: Deploy Cluster Autoscaler on EKS (with Helm)
🧰 Prerequisites

    An existing EKS cluster

    Helm installed (brew install helm or choco install kubernetes-helm)

    kubectl configured for your cluster

    Your node group has the correct IAM permissions (covered below)

1. ✅ Add the Autoscaler Helm Repository


helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo update

2. ✅ Create the IAM Policy for Cluster Autoscaler

This is required for the autoscaler to talk to AWS APIs.


curl -O https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/cluster-autoscaler-policy.json

Attach it to your EKS node group's IAM role, or create a new one if needed.

Example using AWS CLI:


aws iam put-role-policy \
  --role-name <YourNodeGroupIAMRole> \
  --policy-name ClusterAutoscalerPolicy \
  --policy-document file://cluster-autoscaler-policy.json


💡 You can find the node group role in the AWS Console or via Terraform (aws_iam_role.node_group_role.name)

3. ✅ Deploy Cluster Autoscaler via Helm

You need to pass your cluster name, AWS region, and auto-discovery tag (based on your node group’s Name tag).

helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set cloudProvider=aws \
  --set awsRegion=<your-region> \
  --set autoDiscovery.clusterName=<your-cluster-name> \
  --set rbac.create=true \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-local-storage=false \
  --set extraArgs.expander=least-waste \
  --set fullnameOverride=cluster-autoscaler

Replace:

    <your-region> — e.g., us-east-1

    <your-cluster-name> — your EKS cluster name

4. ✅ Add Node Group Tags for Auto-Discovery

In your Terraform aws_eks_node_group, ensure the following tag is present:


tags = {
  "k8s.io/cluster-autoscaler/enabled" = "true"
  "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
}


Re-apply your Terraform changes if needed.


5. ✅ Verify the Cluster Autoscaler is Working


kubectl -n kube-system get pods -l "app.kubernetes.io/name=cluster-autoscaler"
kubectl -n kube-system logs -f deployment/cluster-autoscaler


Look for logs like:

I0720 00:00:00.000000       1 scale_up.go:123] Scale-up: group my-node-group is the best choice


🎯 Optional Tuning

    expander=least-waste helps prefer optimal nodes

    balance-similar-node-groups=true helps distribute workloads evenly



if you want a Terraform module to manage this setup or want to deploy the Cluster Autoscaler 
using a Kubernetes manifest instead of Helm.


Here's how to deploy the Cluster Autoscaler on EKS using Terraform — all within your infrastructure-as-code setup. This includes the IAM permissions, the Kubernetes deployment, and auto-discovery setup.
✅ Terraform: Cluster Autoscaler Deployment on EKS

We’ll split it into 3 main pieces:


1️⃣ IAM Policy for Cluster Autoscaler

First, define the IAM policy for the autoscaler.

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "EKSClusterAutoscalerPolicy"
  description = "IAM policy for Kubernetes Cluster Autoscaler"
  policy      = file("${path.module}/cluster-autoscaler-policy.json")
}


Create the policy file (cluster-autoscaler-policy.json):


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": "*"
    }
  ]
}



2️⃣ Attach Policy to Your Node Group IAM Role

If you already created the role (e.g., aws_iam_role.node_group_role), attach the policy:



resource "aws_iam_role_policy_attachment" "attach_autoscaler_policy" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.node_group_role.name
}



3️⃣ Kubernetes Deployment via Terraform

Install the Cluster Autoscaler using Terraform’s kubernetes_manifest or helm_release. Here's the Helm-based version:


provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.1" # Match EKS and k8s version

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "cloudProvider"
    value = "aws"
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
    name  = "nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  set {
    name  = "tolerations[0].key"
    value = "node-role.kubernetes.io/master"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }
}



4️⃣ Ensure Node Group Has Correct Tags

In your EKS node group resource:



resource "aws_eks_node_group" "node_group" {
  ...

  tags = {
    "k8s.io/cluster-autoscaler/enabled" = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
  }
}



These tags enable auto-discovery of node groups by Cluster Autoscaler.



✅ Done! After Terraform Apply

Run:

kubectl -n kube-system get deployment cluster-autoscaler
kubectl -n kube-system logs -f deployment/cluster-autoscaler


You should see it discovering your node groups and scaling as needed.



to bundle this into a downloadable main.tf


Here is a complete main.tf you can copy and use for deploying Cluster Autoscaler on EKS using Terraform. This includes:

    IAM policy and attachment

    Helm-based autoscaler deployment

    Correct tagging of the node group


📄 main.tf


provider "aws" {
  region = var.region
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "EKSClusterAutoscalerPolicy"
  description = "IAM policy for Kubernetes Cluster Autoscaler"
  policy      = file("${path.module}/cluster-autoscaler-policy.json")
}

resource "aws_iam_role_policy_attachment" "attach_autoscaler_policy" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.node_group_role.name
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"

  tags = {
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"   = "owned"
  }
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.1"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "cloudProvider"
    value = "aws"
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
    name  = "fullnameOverride"
    value = "cluster-autoscaler"
  }
}



📄 cluster-autoscaler-policy.json

Create this in the same directory:


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": "*"
    }
  ]
}



📄 variables.tf


variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS Cluster name"
}



if you'd like to:

    Include this in a module structure

    Add support for multiple node groups

    Automatically install kubectl/aws-auth mappings

I'm happy to expand it further.



— here’s an improved version of the setup using a Terraform module structure with proper separation. This will:

    Organize your EKS + Cluster Autoscaler infrastructure cleanly

    Allow easier reuse and expansion

📦 Module Structure


terraform-eks-cluster-autoscaler/
├── main.tf
├── variables.tf
├── outputs.tf
├── cluster-autoscaler-policy.json
└── modules/
    └── eks/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf



✅ Root main.tf


module "eks" {
  source        = "./modules/eks"
  cluster_name  = var.cluster_name
  region        = var.region
  private_subnet_ids = var.private_subnet_ids
}



✅ Root variables.tf


variable "region" {
  description = "AWS Region"
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for EKS worker nodes"
}




✅ Module: modules/eks/main.tf


provider "aws" {
  region = var.region
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "EKSClusterAutoscalerPolicy"
  description = "IAM policy for Kubernetes Cluster Autoscaler"
  policy      = file("${path.module}/cluster-autoscaler-policy.json")
}

resource "aws_iam_role" "node_group_role" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_autoscaler_policy" {
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
  role       = aws_iam_role.node_group_role.name
}

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.node_group_role.arn

  vpc_config {
    subnet_ids = var.private_subnet_ids
  }
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"

  tags = {
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"   = "owned"
  }
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.1"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "cloudProvider"
    value = "aws"
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
    name  = "fullnameOverride"
    value = "cluster-autoscaler"
  }
}



🧾 Module: modules/eks/variables.tf



variable "region" {
  type        = string
  description = "AWS region"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs"
}



📁 modules/eks/cluster-autoscaler-policy.json

Same as before — add this file to the modules/eks/ directory:


{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": "*"
    }
  ]
}



✅ How to Deploy



terraform init
terraform plan
terraform apply









