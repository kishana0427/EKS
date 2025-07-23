module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "eks-cluster-autoscaler-irsa"
  attach_cluster_autoscaler_policy = true
  cluster_name = var.cluster_name
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
    }
  }

  tags = {
    "Name" = "eks-cluster-autoscaler-irsa"
  }
}
