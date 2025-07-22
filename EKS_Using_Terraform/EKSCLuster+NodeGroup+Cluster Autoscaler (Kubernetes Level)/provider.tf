provider "aws" {
region = "ap-south-1"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config" # or use a data source if provisioning kubeconfig
  }
}
