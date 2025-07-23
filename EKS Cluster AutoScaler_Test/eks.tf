######################

#eks.tf

######################


module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = var.cluster_name
  cluster_version = "1.29"
  subnets         = aws_subnet.private[*].id
  vpc_id          = aws_vpc.main.id

  enable_irsa = true

  node_groups = {
    eks_nodes = {
      desired_capacity = 2
      max_capacity     = 5
      min_capacity     = 1

      instance_types = ["t3.medium"]

      subnet_ids = aws_subnet.private[*].id
    }
  }

  tags = {
    "Environment" = "production"
    "Terraform"   = "true"
  }
}
