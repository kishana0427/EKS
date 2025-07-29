Here's another simpler way to create an IRSA Role for the EKS Cluster Autoscaler using Terraform without modules, giving you full control and clarity. This approach assumes:

You already have an EKS cluster running.

You know your OIDC provider URL.

You deploy Cluster Autoscaler with Helm or YAML, and just need the IRSA set up with Terraform.

🛠 Alternative Method: Manual IRSA Setup (Step-by-Step)
1. OIDC Provider (if not already set up)
If your EKS cluster doesn't yet have an IAM OIDC provider configured, create one:



data "aws_eks_cluster" "eks" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = var.cluster_name
}

data "tls_certificate" "eks_oidc" {
  url = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.eks.identity[0].oidc[0].issuer
}



 IAM Role for Cluster Autoscaler




data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "cluster-autoscaler-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}




Attach Policy to Role
Use AWS-managed or a custom policy:


resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}


✅ You can replace with a custom least-privilege policy if needed.


Kubernetes Service Account with Annotation
Use the Kubernetes Terraform provider:

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }
}



5. Deploy Cluster Autoscaler
When deploying the Cluster Autoscaler (via Helm or YAML), just reference the service account:


serviceAccount:
  name: cluster-autoscaler
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/cluster-autoscaler-irsa



✅ Benefits of This Method
Full control over IAM role & service account.

No use of external modules (everything is visible and tweakable).

Reusable for other IRSA-based services.



