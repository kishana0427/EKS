output "eks_cluster_name" {
  value = aws_eks_cluster.mrcet_eks_cluster.name
}

output "vpc_id" {
  value = aws_vpc.mrcet_eks_vpc.id
}
