##################
#variables.tf
##################

variable "region" {
  default = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "azs" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  default = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "cluster_name" {
  default = "eks-prod-cluster"
}
