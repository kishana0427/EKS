{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::440878854771:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/F9715789C8149BEC2CAA33249B0FF754"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.ap-south-1.amazonaws.com/id/F9715789C8149BEC2CAA33249B0FF754:sub": "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }
  ]
}


