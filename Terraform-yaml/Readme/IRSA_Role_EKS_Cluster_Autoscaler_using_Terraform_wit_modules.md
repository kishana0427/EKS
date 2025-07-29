To configure an IRSA (IAM Roles for Service Accounts) for the Cluster Autoscaler in Amazon EKS using Terraform, you need to:

Create an IAM Role with a trust policy for the EKS OIDC provider.

Attach the required policy to that role.

Associate the IAM role with the Kubernetes service account used by Cluster Autoscaler.

Deploy the Cluster Autoscaler with that service account.

✅ Step-by-step Terraform Setup
1. Get the EKS OIDC provider
You need the EKS OIDC provider URL and ARN. If you're creating your cluster with Terraform, get this info from the EKS module output or retrieve it manually.

2. IAM Role for Cluster Autoscaler (IRSA Role)


resource "aws_iam_openid_connect_provider" "eks" {
  url             = "https://oidc.eks.<region>.amazonaws.com/id/<eks-cluster-id>"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["<thumbprint>"]
}

data "aws_iam_policy_document" "cluster_autoscaler_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.<region>.amazonaws.com/id/<eks-cluster-id>:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "eks-cluster-autoscaler-irsa"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume_role.json
}


3. Attach IAM Policy to the Role
Use the managed AWS policy or create a custom one:


resource "aws_iam_role_policy_attachment" "cluster_autoscaler_attach" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}




resource "aws_iam_role_policy_attachment" "cluster_autoscaler_attach" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}


Alternatively, for least privilege, use the official recommended Cluster Autoscaler policy.

4. Create Kubernetes Service Account
Use Terraform Kubernetes provider to create the service account:


provider "kubernetes" {
  host                   = <EKS API server endpoint>
  cluster_ca_certificate = base64decode(<EKS CA>)
  token                  = <auth token>
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
Make sure the Cluster Autoscaler deployment references the service account cluster-autoscaler in the kube-system namespace.


Optional: Use terraform-aws-eks module for IRSA
If you're using the Terraform AWS EKS module, it has built-in support for IRSA.

Example:

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "my-cluster"
  cluster_version = "1.29"
  ...

  eks_managed_node_groups = {
    ...
  }

  # Enable IRSA
  enable_irsa = true
}

module "cluster_autoscaler_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name_prefix           = "cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }
}



✅ Summary
Use IRSA to securely grant permissions to Cluster Autoscaler.

Attach a least-privilege IAM policy for autoscaling.

Ensure proper annotations in the Kubernetes service account.

Let me know if you want a complete working example or Helm chart values too.
