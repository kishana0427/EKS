
####################

#security.tf

###################


resource "aws_security_group" "eks_nodes_sg" {
  name        = "eks-nodes-sg"
  description = "Allow all EKS node traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name" = "eks-nodes-sg"
  }
}
