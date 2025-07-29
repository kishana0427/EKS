resource "aws_iam_role" "autoscaler_irsa_role" {
  name = "cluster-autoscaler-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::440878854771:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/D78897CAE56BF68A6AC531C9699ECBA6"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "oidc.eks.ap-south-1.amazonaws.com/id/D78897CAE56BF68A6AC531C9699ECBA6:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "autoscaler_attach" {
  role       = aws_iam_role.autoscaler_irsa_role.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}


#resource "aws_iam_role_policy_attachment" "autoscalling_fullaccess_attach" {
#  role       = aws_iam_role.autoscaler_irsa_role.name
#  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
#}


#eksctl utils associate-iam-oidc-provider \
#  --region ap-south-1 \
#  --cluster my-eks-cluster \
#  --approve
#2025-07-28 05:10:46 [ℹ]  will create IAM Open ID Connect provider for cluster "my-eks-cluster" in "ap-south-1"
#2025-07-28 05:10:46 [✔]  created IAM Open ID Connect provider for cluster "my-eks-cluster" in "ap-south-1"



