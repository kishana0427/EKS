resource "aws_iam_role" "autoscaler_irsa_role" {
  name = "EKSClusterAutoscalerIRSA"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::440878854771:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/F9715789C8149BEC2CAA33249B0FF754"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "oidc.eks.ap-south-1.amazonaws.com/id/F9715789C8149BEC2CAA33249B0FF754:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
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



Additional Notes:
Ensure that aws_iam_policy.cluster_autoscaler is properly defined elsewhere in your Terraform configuration.

If it’s not defined yet, you can attach the AWS-managed policy for Cluster Autoscaler like this:





policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"






Let me know if you'd like help creating a custom IAM policy for Cluster Autoscaler.




Great! Here's a recommended directory structure for an EKS project using Terraform with IRSA (IAM Roles for Service Accounts) configured for things like the Cluster Autoscaler:


✅ Recommended Terraform Project Structure for EKS + IRSA


terraform-eks-project/
├── main.tf
├── variables.tf
├── outputs.tf
├── provider.tf
├── versions.tf
├── modules/
│   └── eks/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── irsa/
│       │   └── iam_autoscaler_irsa.tf
├── policies/
│   └── cluster_autoscaler_policy.json
├── terraform.tfvars
└── README.md

📁 File/Folder Descriptions


| File/Folder                               | Purpose                                                    |
| ----------------------------------------- | ---------------------------------------------------------- |
| `main.tf`                                 | Entry point to call modules, including EKS, VPC, IAM, etc. |
| `variables.tf`                            | Inputs used throughout the root module.                    |
| `outputs.tf`                              | Outputs from the root module.                              |
| `provider.tf`                             | AWS provider configuration.                                |
| `versions.tf`                             | Terraform and provider version constraints.                |
| `terraform.tfvars`                        | Concrete values for declared variables.                    |
| `modules/eks/`                            | Custom module for provisioning the EKS cluster.            |
| `modules/eks/irsa/iam_autoscaler_irsa.tf` | IRSA role definition for Cluster Autoscaler.               |
| `policies/cluster_autoscaler_policy.json` | JSON IAM policy doc for the autoscaler.                    |
| `README.md`                               | Documentation for the project.                             |



🛠 How You Might Reference the IRSA Role
Inside your modules/eks/main.tf, you might do:


module "cluster_autoscaler_irsa" {
  source = "./irsa"
}


Or just define the IRSA directly in irsa/ if it's tightly coupled to the EKS module.



🧩 Sample Policy File (Optional)
Save this as policies/cluster_autoscaler_policy.json if you want to use a custom policy instead of AWS-managed ones:



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



And attach it using a resource like:


resource "aws_iam_policy" "cluster_autoscaler" {
  name   = "EKSClusterAutoscalerPolicy"
  policy = file("${path.module}/../../policies/cluster_autoscaler_policy.json")
}



Let me know if you'd like a main.tf example that puts it all together!



Here’s a full main.tf example to tie everything together, using the directory structure I shared. This assumes:

You're provisioning an EKS cluster.

You're using an IRSA role for the Cluster Autoscaler.

You optionally have a custom IAM policy JSON in the policies/ folder.

📄 main.tf (Root Module)


This includes the IRSA setup using iam_autoscaler_irsa.tf in the same module.


resource "aws_iam_policy" "cluster_autoscaler" {
  name   = "EKSClusterAutoscalerPolicy"
  policy = file("${path.module}/../../policies/cluster_autoscaler_policy.json")
}

module "cluster_autoscaler_irsa" {
  source = "./irsa"
}

# Optionally, output role ARN for verification/use in Helm chart
output "cluster_autoscaler_irsa_role_arn" {
  value = aws_iam_role.autoscaler_irsa_role.arn
}



📄 modules/eks/irsa/iam_autoscaler_irsa.tf
This is the file you originally asked about, corrected:


resource "aws_iam_role" "autoscaler_irsa_role" {
  name = "EKSClusterAutoscalerIRSA"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::440878854771:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/F9715789C8149BEC2CAA33249B0FF754"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "oidc.eks.ap-south-1.amazonaws.com/id/F9715789C8149BEC2CAA33249B0FF754:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
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





📄 variables.tf (Root Module)


variable "aws_region" {}
variable "cluster_name" {}
variable "cluster_version" {
  default = "1.29"
}
variable "vpc_id" {}
variable "subnet_ids" {
  type = list(string)
}
variable "node_groups" {
  type = map(any)
}



This structure allows:

Reusability of your EKS module.

Clean separation of IRSA roles and IAM policies.

Easy extension if you want to add more IRSA roles for other workloads (like external-dns, Fluent Bit, etc.).

Would you like an example Helm release block for deploying the Cluster Autoscaler with this IRSA role?





